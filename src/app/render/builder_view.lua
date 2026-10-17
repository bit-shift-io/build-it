-- Draws the builder: the draft's live mesh through the orbit camera, and the
-- sidebar. Never calls the baker (docs/CONTEXT.md "Baker"): the draft is
-- meshed (src/game/blocks/mesher.lua), projected on the CPU by
-- src/app/builder_camera.lua, and lit and depth-tested by the baker's block
-- shader, which takes vertices already in screen pixels with a clip z.
local Model = require("src.game.blocks.model")
local Mesher = require("src.game.blocks.mesher")
local Draft = require("src.game.builder.draft")
local Traits = require("src.game.builder.traits")
local BuilderCamera = require("src.app.builder_camera")
local Baker = require("src.app.bake.baker")
local Screen = require("src.app.screen")

local BuilderView = {}

local SHADER_PATH = "src/app/bake/block_shader.glsl"

-- The block shader's layout (Baker.VERTEX_FORMAT); only the layout and
-- material ids are shared, the builder never bakes.
local VERTEX_FORMAT = Baker.VERTEX_FORMAT

-- The baseplate's slab reaches this far below its top, in layers; matches
-- src/game/builder/pick.lua, so what is drawn is what is picked.
local BASEPLATE_THICKNESS = 0.5
local GHOST_ALPHA = 0.45

local SIDEBAR_BACKGROUND = { 0.13, 0.14, 0.16, 1 }
local BUTTON_COLOR = { 0.24, 0.26, 0.3, 1 }
local TEXT_COLOR = { 0.92, 0.92, 0.92, 1 }
local WARNING_COLOR = { 1, 0.6, 0.4, 1 }
local SELECTED_COLOR = { 1, 0.85, 0.3, 1 }
local FIELD_COLOR = { 0.08, 0.09, 0.1, 1 }
local PLACEHOLDER_COLOR = { 0.55, 0.55, 0.55, 1 }
local HEADING_COLOR = { 0.7, 0.75, 0.85, 1 }
local SHORT_COLOR = { 1, 0.3, 0.3, 1 }
local OK_COLOR = { 0.5, 0.85, 0.5, 1 }

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

-- The held brick at placement cell `place`, as Draft.place would put it.
local function ghostTriangles(place, held, cfg)
	local ghost = Draft.new()
	ghost.width, ghost.depth = cfg.maxBaseplate, cfg.maxBaseplate
	Draft.place(ghost, place.x, place.y, place.z, cfg, held)
	return Mesher.mesh(Draft.toModel(ghost, cfg))
end

local function projectedMesh(view, triangles, alpha)
	local vertices = {}
	for i, v in ipairs(triangles) do
		local sx, sy, z = BuilderCamera.project(view, v.x, v.y, v.z)
		vertices[i] = { sx, sy, z, v.r, v.g, v.b, alpha, v.nx, v.ny, v.nz, Baker.materialId(v), v.x, v.y, v.z }
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
		local ghostMesh = projectedMesh(view, ghostTriangles(ghost, screen.held, screen.cfg), GHOST_ALPHA)
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

-- Whether sidebar button `b` is on: the held brick's current choice, the
-- name field while typing, Open while browsing, the design being edited,
-- or an armed Delete.
local function selected(screen, b)
	if b.kind == "name" then
		return screen.typingName
	elseif b.kind == "open" then
		return screen.browsing
	elseif b.kind == "expand" then
		return b.value == screen.designId
	elseif b.kind == "deleteVersion" then
		return b.armed
	end
	return screen.held[b.kind] ~= nil and screen.held[b.kind] == b.value
end

-- The name field: the typed name, a caret while typing, or a placeholder.
local function drawNameField(screen, b, font)
	love.graphics.setColor(FIELD_COLOR)
	love.graphics.rectangle("fill", b.x, b.y, b.width, b.height, 4, 4)
	local text, color = screen.name, TEXT_COLOR
	if screen.typingName then
		text = text .. "|"
	elseif text == "" then
		text, color = "Click to name", PLACEHOLDER_COLOR
	end
	love.graphics.setColor(color)
	love.graphics.printf(text, b.x + 8, b.y + (b.height - font:getHeight()) / 2, b.width - 16, "left")
end

local HELP = table.concat({
	"Left click: place",
	"Shift+click: paint",
	"Right click: remove",
	"Right drag: orbit",
	"Wheel: zoom",
	"R: turn brick",
	"Ctrl+Z: undo",
	"Ctrl+Shift+Z: redo",
	"Esc: back",
}, "\n")

-- The sidebar: the baseplate size and its resize buttons, the last message
-- (a refused resize or save, a save, unreadable design files), the design's
-- name and actions, and the held brick's shape (plain or function brick),
-- material and paint -- or, while browsing, the library's designs, one
-- expanded into its version rows (Open and Delete).
function BuilderView.drawSidebar(screen, buttons)
	local _, h = Screen.dimensions()
	local d, cfg = screen.draft, screen.cfg
	local font = love.graphics.getFont()
	love.graphics.push("all")
	love.graphics.setColor(SIDEBAR_BACKGROUND)
	love.graphics.rectangle("fill", 0, 0, cfg.sidebarWidth, h)
	love.graphics.setColor(TEXT_COLOR)
	love.graphics.print("Builder", 16, 16)
	love.graphics.print(string.format("Baseplate %d x %d tiles", d.width, d.depth), 16, 40)
	local lastResize = nil
	for _, b in ipairs(buttons) do
		if b.heading then
			love.graphics.setColor(TEXT_COLOR)
			love.graphics.print(b.heading, 16, b.y - font:getHeight() - 4)
		end
		if b.kind == "paint" then
			local c = cfg.palette[b.value]
			love.graphics.setColor(c[1], c[2], c[3], 1)
			love.graphics.rectangle("fill", b.x, b.y, b.width, b.height, 3, 3)
		elseif b.kind == "name" then
			drawNameField(screen, b, font)
		else
			love.graphics.setColor(BUTTON_COLOR)
			love.graphics.rectangle("fill", b.x, b.y, b.width, b.height, 4, 4)
			love.graphics.setColor(b.armed and WARNING_COLOR or TEXT_COLOR)
			love.graphics.printf(b.label, b.x, b.y + (b.height - font:getHeight()) / 2, b.width, "center")
		end
		if selected(screen, b) then
			love.graphics.setColor(SELECTED_COLOR)
			love.graphics.setLineWidth(2)
			love.graphics.rectangle("line", b.x - 1, b.y - 1, b.width + 2, b.height + 2, 4, 4)
		end
		if b.kind == "resize" then
			lastResize = b
		end
	end
	if screen.message and lastResize then
		love.graphics.setColor(WARNING_COLOR)
		love.graphics.printf(screen.message, 16, lastResize.y + lastResize.height + 8, cfg.sidebarWidth - 32)
	end
	love.graphics.pop()
end

local function capitalised(s)
	return s:sub(1, 1):upper() .. s:sub(2)
end

-- Prints `text` wrapped to the panel at y in `color`; returns the y below.
local function paragraph(text, x, y, width, color, font)
	love.graphics.setColor(color)
	love.graphics.printf(text, x, y, width)
	local _, lines = font:getWrap(text, width)
	return y + #lines * font:getHeight()
end

-- The info panel at the window's right edge (`panel`, a rectangle):
-- `info` (BuilderScreen.info) as the draft's trait totals, its cost against
-- storage -- red where short -- and the design rules it breaks; the
-- controls at the bottom.
function BuilderView.drawInfo(screen, panel, info)
	local font = love.graphics.getFont()
	local line = font:getHeight()
	local x, width = panel.x + 16, panel.width - 32
	love.graphics.push("all")
	love.graphics.setColor(SIDEBAR_BACKGROUND)
	love.graphics.rectangle("fill", panel.x, panel.y, panel.width, panel.height)

	local y = 16
	y = paragraph("Traits", x, y, width, HEADING_COLOR, font) + 4
	for _, name in ipairs(Traits.NAMES) do
		love.graphics.setColor(TEXT_COLOR)
		love.graphics.print(capitalised(name), x, y)
		love.graphics.printf(tostring(info.traits[name]), x, y, width, "right")
		y = y + line
	end

	y = paragraph("Auras", x, y + 12, width, HEADING_COLOR, font) + 4
	for _, name in ipairs(Traits.AURA_NAMES) do
		love.graphics.setColor(TEXT_COLOR)
		love.graphics.print(name == "walkSpeed" and "Walk speed" or "Harvest rate", x, y)
		love.graphics.printf(string.format("+%d%%", math.floor(info.auras[name] * 100 + 0.5)), x, y, width, "right")
		y = y + line
	end

	y = paragraph("Cost (need / have)", x, y + 12, width, HEADING_COLOR, font) + 4
	for _, row in ipairs(info.cost) do
		love.graphics.setColor(row.short and SHORT_COLOR or TEXT_COLOR)
		love.graphics.print(capitalised(row.item), x, y)
		love.graphics.printf(string.format("%d / %d", row.need, row.have), x, y, width, "right")
		y = y + line
	end

	y = paragraph("Problems", x, y + 12, width, HEADING_COLOR, font) + 4
	if #info.problems == 0 then
		paragraph("None: ready to save.", x, y, width, OK_COLOR, font)
	end
	for _, text in ipairs(info.problems) do
		y = paragraph(text, x, y, width, WARNING_COLOR, font) + 4
	end

	local _, h = Screen.dimensions()
	love.graphics.setColor(TEXT_COLOR)
	love.graphics.printf(HELP, x, h - 9 * line - 16, width)
	love.graphics.pop()
end

return BuilderView
