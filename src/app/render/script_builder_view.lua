-- Draws the script builder (src/app/screens/script_builder.lua): the
-- design's geometry (selected nodes tinted), its footprint square and its
-- snapped ports through the orbit camera, and the status line. The top
-- bar, tree panel and menu draw themselves (src/app/ui/). Never calls the baker (docs/CONTEXT.md
-- "Baker"): geometry is projected on the CPU by src/app/builder_camera.lua
-- and lit and depth-tested by the baker's block shader, which takes vertices
-- already in screen pixels with a clip z (Baker.VERTEX_FORMAT,
-- docs/memory/love-12-mesh-vertex-format.md, love-12-depth-canvas.md).
--
-- Geometry is in tiles; the camera works in builder studs, so every point
-- is scaled by studsPerTile before projecting.
local BuilderCamera = require("src.app.builder_camera")
local Baker = require("src.app.bake.baker")
local Scene = require("src.game.builder.scene")
local Screen = require("src.app.screen")

local ScriptBuilderView = {}

local SHADER_PATH = "src/app/bake/block_shader.glsl"

-- The footprint square lies this far below the ground, in studs, so faces
-- resting on the ground draw over it; its border a little above the fill.
local FOOTPRINT_DROP = 0.02
local FOOTPRINT_FILL = { 0.3, 0.55, 0.35 }
local FOOTPRINT_BORDER = { 0.55, 0.9, 0.6 }
-- The border's width, in studs, inside the square's edge.
local BORDER_WIDTH = 0.2
-- Port markers: a square this many tiles across on each snapped port's
-- position, just above the footprint, coloured by kind like the world's.
local PORT_SIZE = 0.5
local PORT_COLORS = { input = { 0.3, 0.65, 1 }, output = { 1, 0.62, 0.2 } }
-- Selected nodes' geometry is blended this far toward SELECTED_COLOR.
local SELECTED_COLOR = { 0.35, 0.6, 1 }
local SELECTED_BLEND = 0.55
-- The footprint's normal: straight up.
local UP = { 0, 0, 1 }

local STATUS_COLOR = { 0.6, 0.9, 0.6, 1 }
local LOCKED_COLOR = { 1, 0.75, 0.45, 1 }
local TEXT_COLOR = { 0.92, 0.92, 0.92, 1 }
local WARNING_COLOR = { 1, 0.6, 0.4, 1 }

local HELP = "Click: select   Ctrl-click: add   Double-click: rename   Right click: menu   "
	.. "Right drag: orbit   Wheel: zoom   Ctrl+Z/Y: undo/redo   Ctrl+S: save   Esc: back"

local shader = nil
-- Colour and depth targets the size of the window, remade when it resizes.
local targets = nil
-- Stud-space vertices for the screen's current geometry revision.
local cached = { screen = nil, revision = nil, vertices = nil }

local function blockShader(config)
	if not shader then
		shader = love.graphics.newShader(SHADER_PATH)
	end
	local l = config.bake.lightDirection
	local len = math.sqrt(l[1] * l[1] + l[2] * l[2] + l[3] * l[3])
	shader:send("lightDirection", { l[1] / len, l[2] / len, l[3] / len })
	shader:send("ambient", config.bake.ambient)
	return shader
end

local function renderTargets()
	local w, h = Screen.dimensions()
	if not targets or targets.width ~= w or targets.height ~= h then
		if targets then
			targets.color:release()
			targets.depth:release()
		end
		targets = {
			width = w,
			height = h,
			color = love.graphics.newCanvas(w, h),
			depth = love.graphics.newCanvas(w, h, { format = "depth24" }),
		}
	end
	return targets
end

local function studVertex(x, y, z, n, color, material, texture)
	return { x = x, y = y, z = z, nx = n[1], ny = n[2], nz = n[3], r = color[1], g = color[2], b = color[3], material = material, texture = texture }
end

-- A flat rectangle from (x0, y0) to (x1, y1) at height z, facing up.
local function rectangle(out, x0, y0, x1, y1, z, color)
	local c = { { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y1 } }
	for _, i in ipairs({ 1, 3, 2, 1, 4, 3 }) do
		table.insert(out, studVertex(c[i][1], c[i][2], z, UP, color))
	end
end

-- Footprint `f` (in tiles) as a filled square with a border, in studs.
local function footprintSquare(out, f, s)
	local x0, y0 = f.x * s, f.y * s
	local x1, y1 = (f.x + f.width) * s, (f.y + f.depth) * s
	local w, z = BORDER_WIDTH, -FOOTPRINT_DROP / 2
	rectangle(out, x0, y0, x1, y1, -FOOTPRINT_DROP, FOOTPRINT_FILL)
	rectangle(out, x0, y0, x1, y0 + w, z, FOOTPRINT_BORDER)
	rectangle(out, x0, y1 - w, x1, y1, z, FOOTPRINT_BORDER)
	rectangle(out, x0, y0, x0 + w, y1, z, FOOTPRINT_BORDER)
	rectangle(out, x1 - w, y0, x1, y1, z, FOOTPRINT_BORDER)
end

-- A square marker on each port in `ports` (Blueprint roles.ports, tiles), in
-- studs, between the footprint and the ground-level faces.
local function portMarkers(out, ports, s)
	local h, z = PORT_SIZE / 2, -FOOTPRINT_DROP / 4
	for _, port in ipairs(ports) do
		local x, y = port.x, port.y
		rectangle(out, (x - h) * s, (y - h) * s, (x + h) * s, (y + h) * s, z, PORT_COLORS[port.kind])
	end
end

-- Colour (r, g, b) blended toward the selection colour.
local function tinted(r, g, b)
	local t = SELECTED_BLEND
	return { r + (SELECTED_COLOR[1] - r) * t, g + (SELECTED_COLOR[2] - g) * t, b + (SELECTED_COLOR[3] - b) * t }
end

-- The geometry (screen.targets, selected nodes tinted), the footprint
-- square and the port markers as stud-space vertices.
local function studVertices(screen)
	if cached.screen ~= screen or cached.revision ~= screen.revision then
		local s = screen.cfg.studsPerTile
		local out = {}
		if screen.footprint then
			footprintSquare(out, screen.footprint, s)
		end
		portMarkers(out, screen.ports, s)
		for _, target in ipairs(screen.targets) do
			local selected = screen.scene and Scene.isSelected(screen.scene, target.id)
			for _, v in ipairs(target.triangles) do
				local n = { v.nx, v.ny, v.nz }
				local color = selected and tinted(v.r, v.g, v.b) or { v.r, v.g, v.b }
				table.insert(out, studVertex(v.x * s, v.y * s, v.z * s, n, color, v.material, v.texture))
			end
		end
		cached = { screen = screen, revision = screen.revision, vertices = out }
	end
	return cached.vertices
end

local function projectedMesh(view, vertices)
	local out = {}
	for i, v in ipairs(vertices) do
		local sx, sy, z = BuilderCamera.project(view, v.x, v.y, v.z)
		local variant, scale, rotation = Baker.texture(v)
		out[i] = { sx, sy, z, v.r, v.g, v.b, 1, v.nx, v.ny, v.nz, Baker.materialId(v), v.x, v.y, v.z, variant, scale, rotation }
	end
	return love.graphics.newMesh(Baker.VERTEX_FORMAT, out, "triangles", "stream")
end

-- Draws the geometry and its footprint through `view` into the viewport
-- below the top bar.
function ScriptBuilderView.draw(screen, view)
	local t = renderTargets()
	local vertices = studVertices(screen)

	love.graphics.push("all")
	love.graphics.origin()
	love.graphics.setCanvas({ t.color, depthstencil = t.depth })
	love.graphics.clear(Screen.BACKGROUND)
	if #vertices > 0 then
		local mesh = projectedMesh(view, vertices)
		love.graphics.setShader(blockShader(screen.config))
		love.graphics.setColor(1, 1, 1, 1)
		love.graphics.setDepthMode("less", true)
		love.graphics.draw(mesh)
		mesh:release()
	end
	love.graphics.pop()

	love.graphics.push("all")
	love.graphics.setBlendMode("alpha", "premultiplied")
	love.graphics.draw(t.color, 0, 0)
	love.graphics.pop()
end

-- The script's error (or why an edit was refused), the last save, whether
-- the script is locked, and the controls, at the bottom left.
function ScriptBuilderView.drawStatus(screen)
	local w, h = Screen.dimensions()
	local line = love.graphics.getFont():getHeight()
	love.graphics.push("all")
	if screen.message then
		love.graphics.setColor(WARNING_COLOR)
		love.graphics.printf(screen.message, 16, h - 16 - 4 * line, w - 32)
	end
	if screen.status then
		love.graphics.setColor(STATUS_COLOR)
		love.graphics.print(screen.status, 16, h - 16 - 3 * line)
	end
	if screen.locked then
		love.graphics.setColor(LOCKED_COLOR)
		love.graphics.print("Locked script: edit params and code only", 16, h - 16 - 2 * line)
	end
	love.graphics.setColor(TEXT_COLOR)
	love.graphics.print(HELP, 16, h - 16 - line)
	love.graphics.pop()
end

return ScriptBuilderView
