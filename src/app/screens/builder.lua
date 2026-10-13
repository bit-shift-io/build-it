-- The builder screen (docs/CONTEXT.md "Builder"): a live 3D view of the
-- draft on the right, a sidebar on the left. Left-click places a brick on
-- the surface under the cursor; right-click removes the brick under it;
-- right-drag orbits; the wheel zooms. Sidebar buttons resize the baseplate.
--
-- Picking runs through src/game/builder/pick.lua with the ray from the same
-- camera view the screen draws with.
local Draft = require("src.game.builder.draft")
local Pick = require("src.game.builder.pick")
local BuilderCamera = require("src.app.builder_camera")
local BuilderView = require("src.app.render.builder_view")
local Screen = require("src.app.screen")

local BuilderScreen = {}

-- Sidebar layout, in pixels from the window's top-left.
local PAD = 16
local BUTTON_HEIGHT = 32
local BUTTONS_TOP = 72

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

-- The sidebar's buttons: { label, x, y, width, height, dw, dd }, where
-- dw/dd is the change each makes to the baseplate's width/depth in tiles.
function BuilderScreen.buttons(screen)
	local half = (screen.cfg.sidebarWidth - 3 * PAD) / 2
	local rows = {
		{ "Width -", "Width +", dw = 1, dd = 0 },
		{ "Depth -", "Depth +", dw = 0, dd = 1 },
	}
	local out = {}
	for i, row in ipairs(rows) do
		local y = BUTTONS_TOP + (i - 1) * (BUTTON_HEIGHT + PAD / 2)
		table.insert(out, { label = row[1], x = PAD, y = y, width = half, height = BUTTON_HEIGHT, dw = -row.dw, dd = -row.dd })
		table.insert(out, { label = row[2], x = 2 * PAD + half, y = y, width = half, height = BUTTON_HEIGHT, dw = row.dw, dd = row.dd })
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
	return Pick.cast(screen.draft, origin, dir, screen.cfg)
end

local function changed(screen)
	screen.revision = screen.revision + 1
end

local function resize(screen, b)
	local d = screen.draft
	local ok, reason = Draft.resize(d, d.width + b.dw, d.depth + b.dd, screen.cfg)
	screen.message = not ok and REFUSALS[reason] or nil
	if ok then
		changed(screen)
	end
end

local function place(screen, x, y)
	local hit = BuilderScreen.hover(screen, x, y)
	if hit and Draft.place(screen.draft, hit.place.x, hit.place.y, hit.place.z, screen.cfg) then
		changed(screen)
	end
end

local function remove(screen, x, y)
	local hit = BuilderScreen.hover(screen, x, y)
	if hit and hit.brick then
		Draft.remove(screen.draft, hit.brick)
		changed(screen)
	end
end

function BuilderScreen.mousepressed(screen, x, y, button)
	if button == 1 then
		local b = buttonAt(screen, x, y)
		if b then
			resize(screen, b)
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
	if hit and Draft.fits(screen.draft, hit.place.x, hit.place.y, hit.place.z, screen.cfg) then
		ghost = hit.place
	end
	BuilderView.draw(screen, BuilderScreen.view(screen), ghost)
	BuilderView.drawSidebar(screen, BuilderScreen.buttons(screen))
end

return BuilderScreen
