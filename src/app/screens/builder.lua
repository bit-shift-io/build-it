-- The builder screen (docs/CONTEXT.md "Builder"): a live 3D view of the
-- draft on the right, a sidebar on the left. Left-click places a brick on
-- the surface under the cursor; shift-left-click paints the brick under it;
-- right-click removes the brick under it; right-drag orbits; the wheel
-- zooms. R turns the held brick. Ctrl+Z undoes and Ctrl+Shift+Z redoes
-- every draft change. Sidebar buttons resize the baseplate and pick the
-- held brick's shape, material and paint.
--
-- Picking runs through src/game/builder/pick.lua with the ray from the same
-- camera view the screen draws with.
local Draft = require("src.game.builder.draft")
local Pick = require("src.game.builder.pick")
local History = require("src.game.builder.history")
local BuilderCamera = require("src.app.builder_camera")
local BuilderView = require("src.app.render.builder_view")
local Screen = require("src.app.screen")

local BuilderScreen = {}

-- Sidebar layout, in pixels from the window's top-left.
local PAD = 16
local BUTTON_HEIGHT = 32
local BUTTONS_TOP = 72
local GAP = 8
-- Room under the resize rows for the refusal message.
local MESSAGE_HEIGHT = 40
-- Room above each picker section for its heading.
local HEADING_HEIGHT = 20
local SHAPE_COLUMNS, SHAPE_HEIGHT = 3, 28
local SWATCH_COLUMNS, SWATCH_HEIGHT = 4, 24

-- Shown when a resize is refused, keyed by Draft.resize's reason.
local REFUSALS = {
	size = "The baseplate is 1 to 4 tiles a side.",
	bricks = "Bricks sit outside that size.",
}

function BuilderScreen.new(config)
	local cfg = config.builder
	return {
		config = config,
		cfg = cfg,
		draft = Draft.new(),
		-- Undo/redo for every draft change (src/game/builder/history.lua).
		history = History.new(),
		-- The brick in hand: { shape, rotation, material, paint }.
		held = { shape = cfg.held.shape, rotation = cfg.held.rotation, material = cfg.held.material, paint = cfg.held.paint },
		camera = BuilderCamera.new(cfg),
		-- Bumped on every draft change, so the view remeshes only then.
		revision = 0,
		mouseX = nil,
		mouseY = nil,
		-- The right button's press, until release: { x, y, moved }.
		rightPress = nil,
		-- Why the last resize was refused, until the next one succeeds.
		message = nil,
	}
end

-- The 3D view's rectangle: the window right of the sidebar.
function BuilderScreen.viewport(screen)
	local w, h = Screen.dimensions()
	local side = screen.cfg.sidebarWidth
	return { x = side, y = 0, width = w - side, height = h }
end

-- This frame's camera view (src/app/builder_camera.lua).
function BuilderScreen.view(screen)
	return BuilderCamera.view(screen.camera, screen.draft, screen.cfg, BuilderScreen.viewport(screen))
end

local function capitalised(s)
	return s:sub(1, 1):upper() .. s:sub(2)
end

-- Lays `items` ({ label, value }) out in a grid of `columns` from `top`,
-- appending one `kind` button per item to `out`. Returns the y below it.
local function grid(out, screen, kind, items, columns, height, top)
	local width = (screen.cfg.sidebarWidth - 2 * PAD - (columns - 1) * GAP) / columns
	for i, item in ipairs(items) do
		local col, row = (i - 1) % columns, math.floor((i - 1) / columns)
		table.insert(out, {
			kind = kind,
			label = item.label,
			value = item.value,
			x = PAD + col * (width + GAP),
			y = top + row * (height + GAP),
			width = width,
			height = height,
		})
	end
	return top + math.ceil(#items / columns) * (height + GAP)
end

-- The sidebar's buttons, each { kind, label, x, y, width, height, ... }:
--   kind "resize": dw/dd, the change to the baseplate's width/depth in tiles
--   kind "shape" | "material" | "paint": value, what it sets on the held
--     brick (a cfg.bricks name, a cfg.materials name, a cfg.palette index;
--     swatches are labelled "paint:<index>")
-- The first button of each picker kind has `heading`, its section title.
function BuilderScreen.buttons(screen)
	local cfg = screen.cfg
	local half = (cfg.sidebarWidth - 3 * PAD) / 2
	local rows = {
		{ "Width -", "Width +", dw = 1, dd = 0 },
		{ "Depth -", "Depth +", dw = 0, dd = 1 },
	}
	local out = {}
	local y = BUTTONS_TOP
	for _, row in ipairs(rows) do
		table.insert(out, { kind = "resize", label = row[1], x = PAD, y = y, width = half, height = BUTTON_HEIGHT, dw = -row.dw, dd = -row.dd })
		table.insert(out, { kind = "resize", label = row[2], x = 2 * PAD + half, y = y, width = half, height = BUTTON_HEIGHT, dw = row.dw, dd = row.dd })
		y = y + BUTTON_HEIGHT + GAP
	end
	y = y + MESSAGE_HEIGHT

	local sections = {
		{ kind = "shape", heading = "Brick (R turns)", columns = SHAPE_COLUMNS, height = SHAPE_HEIGHT, items = {} },
		{ kind = "material", heading = "Material", columns = 2, height = SHAPE_HEIGHT, items = {} },
		{ kind = "paint", heading = "Paint (shift-click)", columns = SWATCH_COLUMNS, height = SWATCH_HEIGHT, items = {} },
	}
	for _, shape in ipairs(cfg.bricks) do
		table.insert(sections[1].items, { label = shape.name, value = shape.name })
	end
	for _, material in ipairs(cfg.materials) do
		table.insert(sections[2].items, { label = capitalised(material), value = material })
	end
	for i in ipairs(cfg.palette) do
		table.insert(sections[3].items, { label = "paint:" .. i, value = i })
	end
	for _, section in ipairs(sections) do
		local first = #out + 1
		y = grid(out, screen, section.kind, section.items, section.columns, section.height, y + HEADING_HEIGHT)
		out[first].heading = section.heading
	end
	return out
end

local function buttonAt(screen, x, y)
	for _, b in ipairs(BuilderScreen.buttons(screen)) do
		if x >= b.x and x < b.x + b.width and y >= b.y and y < b.y + b.height then
			return b
		end
	end
	return nil
end

-- What the cursor at (x, y) points at in the draft (Pick.cast), or nil.
function BuilderScreen.hover(screen, x, y)
	if x == nil or x < screen.cfg.sidebarWidth then
		return nil
	end
	local origin, dir = BuilderCamera.ray(BuilderScreen.view(screen), x, y)
	return Pick.cast(screen.draft, origin, dir, screen.cfg, screen.held)
end

local function changed(screen)
	screen.revision = screen.revision + 1
end

-- Runs a draft edit (Draft.place, ...) through the undo history, and
-- remeshes when it took. Returns the edit's results.
local function edit(screen, change, ...)
	local results = { History.apply(screen.history, screen.draft, change, ...) }
	if results[1] then
		changed(screen)
	end
	return unpack(results, 1, table.maxn(results))
end

local function resize(screen, b)
	local d = screen.draft
	local ok, reason = edit(screen, Draft.resize, d.width + b.dw, d.depth + b.dd, screen.cfg)
	screen.message = not ok and REFUSALS[reason] or nil
end

local function place(screen, x, y)
	local hit = BuilderScreen.hover(screen, x, y)
	if hit then
		edit(screen, Draft.place, hit.place.x, hit.place.y, hit.place.z, screen.cfg, screen.held)
	end
end

local function paint(screen, x, y)
	local hit = BuilderScreen.hover(screen, x, y)
	if hit and hit.brick then
		edit(screen, Draft.paint, hit.brick, screen.held.paint)
	end
end

local function remove(screen, x, y)
	local hit = BuilderScreen.hover(screen, x, y)
	if hit and hit.brick then
		edit(screen, Draft.remove, hit.brick)
	end
end

local function press(screen, b)
	if b.kind == "resize" then
		resize(screen, b)
	else
		screen.held[b.kind] = b.value
	end
end

-- Whether either of a modifier's keys ("ctrl", "shift") is held.
local function modifier(name)
	return love.keyboard.isDown("l" .. name) or love.keyboard.isDown("r" .. name)
end

function BuilderScreen.keypressed(screen, key)
	if key == "r" then
		screen.held.rotation = (screen.held.rotation + 1) % 4
	elseif key == "z" and modifier("ctrl") then
		local step = modifier("shift") and History.redo or History.undo
		if step(screen.history, screen.draft) then
			screen.message = nil
			changed(screen)
		end
	end
end

function BuilderScreen.mousepressed(screen, x, y, button)
	if button == 1 then
		local b = buttonAt(screen, x, y)
		if b then
			press(screen, b)
		elseif modifier("shift") then
			paint(screen, x, y)
		else
			place(screen, x, y)
		end
	elseif button == 2 then
		screen.rightPress = { x = x, y = y, moved = 0 }
	end
end

-- A right release that barely moved is a click: remove the brick under it.
function BuilderScreen.mousereleased(screen, x, y, button)
	local press = screen.rightPress
	if button == 2 and press then
		screen.rightPress = nil
		if press.moved < screen.cfg.clickSlop then
			remove(screen, x, y)
		end
	end
end

function BuilderScreen.mousemoved(screen, x, y, dx, dy)
	screen.mouseX, screen.mouseY = x, y
	local press = screen.rightPress
	if press then
		press.moved = press.moved + math.abs(dx) + math.abs(dy)
		if press.moved >= screen.cfg.clickSlop then
			BuilderCamera.orbit(screen.camera, dx, dy, screen.cfg)
		end
	end
end

function BuilderScreen.wheelmoved(screen, _, y)
	BuilderCamera.zoomBy(screen.camera, y, screen.draft, screen.cfg)
end

function BuilderScreen.draw(screen)
	local hit = BuilderScreen.hover(screen, screen.mouseX, screen.mouseY)
	local ghost = nil
	if hit and Draft.fits(screen.draft, hit.place.x, hit.place.y, hit.place.z, screen.cfg, screen.held) then
		ghost = hit.place
	end
	BuilderView.draw(screen, BuilderScreen.view(screen), ghost)
	BuilderView.drawSidebar(screen, BuilderScreen.buttons(screen))
end

return BuilderScreen
