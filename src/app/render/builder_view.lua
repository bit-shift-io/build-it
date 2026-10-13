-- Draws the builder: the draft's live mesh through the orbit camera, and the
-- sidebar. Never calls the baker (docs/CONTEXT.md "Baker"): the draft is
-- meshed (src/game/blocks/mesher.lua), projected on the CPU by
-- src/app/builder_camera.lua, and lit and depth-tested by the baker's block
-- shader, which takes vertices already in screen pixels with a clip z.
local Model = require("src.game.blocks.model")
local Mesher = require("src.game.blocks.mesher")
local Draft = require("src.game.builder.draft")
local BuilderCamera = require("src.app.builder_camera")
local Screen = require("src.app.screen")

local BuilderView = {}

local SHADER_PATH = "src/app/bake/block_shader.glsl"

-- Same layout as the baker's (docs/memory/love-12-mesh-vertex-format.md).
local VERTEX_FORMAT = {
	{ name = "VertexPosition", format = "floatvec3", location = 0 },
	{ name = "VertexColor", format = "floatvec4", location = 2 },
	{ name = "VertexNormal", format = "floatvec3", location = 3 },
}

-- The baseplate's slab reaches this far below its top, in layers; matches
-- src/game/builder/pick.lua, so what is drawn is what is picked.
local BASEPLATE_THICKNESS = 0.5
local GHOST_ALPHA = 0.45

local SIDEBAR_BACKGROUND = { 0.13, 0.14, 0.16, 1 }
local BUTTON_COLOR = { 0.24, 0.26, 0.3, 1 }
local TEXT_COLOR = { 0.92, 0.92, 0.92, 1 }
local WARNING_COLOR = { 1, 0.6, 0.4, 1 }

local shader = nil
-- Colour and depth targets the size of the window, remade when it resizes.
local targets = nil
-- Mesher output for the screen's current draft revision.
local cached = { screen = nil, revision = nil, triangles = nil }

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

-- The baseplate as one cell per stud a layer below z = 0, in a checker of
-- two greens so the stud grid shows. Squashed to its thickness when drawn.
local function baseplateModel(draft, cfg)
	local studs = cfg.studsPerTile
	local m = Model.new(studs, draft.width, draft.depth)
	for x = 0, draft.width * studs - 1 do
		for y = 0, draft.depth * studs - 1 do
			local color = (x + y) % 2 == 0 and cfg.colors.baseplate or cfg.colors.baseplateStud
			Model.addCell(m, { x = x, y = y, z = -1, color = color })
		end
	end
	return m
end

local function draftTriangles(screen)
	if cached.screen ~= screen or cached.revision ~= screen.revision then
		local triangles = {}
		for _, v in ipairs(Mesher.mesh(baseplateModel(screen.draft, screen.cfg))) do
			v.z = v.z * BASEPLATE_THICKNESS
			table.insert(triangles, v)
		end
		if #screen.draft.bricks > 0 then
			for _, v in ipairs(Mesher.mesh(Draft.toModel(screen.draft, screen.cfg))) do
				table.insert(triangles, v)
			end
		end
		cached = { screen = screen, revision = screen.revision, triangles = triangles }
	end
	return cached.triangles
end

local function ghostTriangles(place, cfg)
	local ghost = Draft.new()
	table.insert(ghost.bricks, { x = place.x, y = place.y, z = place.z, width = cfg.brick.width, depth = cfg.brick.depth })
	return Mesher.mesh(Draft.toModel(ghost, cfg))
end

local function projectedMesh(view, triangles, alpha)
	local vertices = {}
	for i, v in ipairs(triangles) do
		local sx, sy, z = BuilderCamera.project(view, v.x, v.y, v.z)
		vertices[i] = { sx, sy, z, v.r, v.g, v.b, alpha, v.nx, v.ny, v.nz }
	end
	return love.graphics.newMesh(VERTEX_FORMAT, vertices, "triangles", "stream")
end

-- Draws the draft (and the ghost brick at `ghost`, a placement cell, if
-- any) through `view` into the viewport right of the sidebar.
function BuilderView.draw(screen, view, ghost)
	local t = renderTargets()
	local mesh = projectedMesh(view, draftTriangles(screen), 1)

	love.graphics.push("all")
	love.graphics.origin()
	love.graphics.setCanvas({ t.color, depthstencil = t.depth })
	love.graphics.clear(Screen.BACKGROUND)
	love.graphics.setShader(blockShader(screen.config))
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.setDepthMode("less", true)
	love.graphics.draw(mesh)
	if ghost then
		-- Depth-tested against the draft, but never hides what is behind it.
		local ghostMesh = projectedMesh(view, ghostTriangles(ghost, screen.cfg), GHOST_ALPHA)
		love.graphics.setDepthMode("lequal", false)
		love.graphics.draw(ghostMesh)
		ghostMesh:release()
	end
	love.graphics.pop()
	mesh:release()

	love.graphics.push("all")
	love.graphics.setBlendMode("alpha", "premultiplied")
	love.graphics.draw(t.color, 0, 0)
	love.graphics.pop()
end

-- The sidebar: the baseplate size, its resize buttons, and why the last
-- resize was refused.
function BuilderView.drawSidebar(screen, buttons)
	local _, h = Screen.dimensions()
	local d = screen.draft
	love.graphics.push("all")
	love.graphics.setColor(SIDEBAR_BACKGROUND)
	love.graphics.rectangle("fill", 0, 0, screen.cfg.sidebarWidth, h)
	love.graphics.setColor(TEXT_COLOR)
	love.graphics.print("Builder", 16, 16)
	love.graphics.print(string.format("Baseplate %d x %d tiles", d.width, d.depth), 16, 40)
	for _, b in ipairs(buttons) do
		love.graphics.setColor(BUTTON_COLOR)
		love.graphics.rectangle("fill", b.x, b.y, b.width, b.height, 4, 4)
		love.graphics.setColor(TEXT_COLOR)
		love.graphics.printf(b.label, b.x, b.y + (b.height - love.graphics.getFont():getHeight()) / 2, b.width, "center")
	end
	local last = buttons[#buttons]
	if screen.message then
		love.graphics.setColor(WARNING_COLOR)
		love.graphics.printf(screen.message, 16, last.y + last.height + 16, screen.cfg.sidebarWidth - 32)
	end
	love.graphics.setColor(TEXT_COLOR)
	love.graphics.printf("Left click: place\nRight click: remove\nRight drag: orbit\nWheel: zoom\nEsc: back", 16, h - 112, screen.cfg.sidebarWidth - 32)
	love.graphics.pop()
end

return BuilderView
