-- App flow: which screen is showing, and the switch between them. B opens
-- the builder from the world; Esc goes back (unless the builder is taking
-- typed text, when Esc only stops the typing). main.lua and the test harness
-- (tests/support/game_harness.lua) route every LÖVE callback here, so
-- headless tests drive the same path as the app.
--
-- Only the showing screen updates: the world stands still while the
-- builder is open. The builder never touches the world (docs/CONTEXT.md
-- "Builder"), and keeps its draft between visits.
local WorldScreen = require("src.app.screens.world")
local BuilderScreen = require("src.app.screens.builder")

local Flow = {}

local SCREENS = { world = WorldScreen, builder = BuilderScreen }

function Flow.new(ctx, config)
	return {
		screen = "world",
		world = WorldScreen.new(ctx),
		builder = BuilderScreen.new(config),
	}
end

-- Calls the showing screen's handler for `event`, if it has one.
local function dispatch(flow, event, ...)
	local module = SCREENS[flow.screen]
	if module[event] then
		module[event](flow[flow.screen], ...)
	end
end

-- One fixed step of the showing screen.
function Flow.update(flow, dt)
	dispatch(flow, "update", dt)
end

function Flow.draw(flow)
	dispatch(flow, "draw")
end

function Flow.keypressed(flow, key)
	if flow.screen == "world" and key == "b" then
		flow.screen = "builder"
	elseif flow.screen == "builder" and key == "escape" and not BuilderScreen.typing(flow.builder) then
		flow.screen = "world"
	else
		dispatch(flow, "keypressed", key)
	end
end

-- Typed text (love.textinput), e.g. a design's name.
function Flow.textinput(flow, text)
	dispatch(flow, "textinput", text)
end

function Flow.mousepressed(flow, x, y, button)
	dispatch(flow, "mousepressed", x, y, button)
end

function Flow.mousereleased(flow, x, y, button)
	dispatch(flow, "mousereleased", x, y, button)
end

function Flow.mousemoved(flow, x, y, dx, dy)
	dispatch(flow, "mousemoved", x, y, dx, dy)
end

function Flow.wheelmoved(flow, x, y)
	dispatch(flow, "wheelmoved", x, y)
end

return Flow
