-- App flow: which screen is showing, and the switch between them. The app
-- launches on the title screen (Continue / New game); B opens the builder
-- from the world; Esc goes back (unless the builder is taking typed text,
-- when Esc only stops the typing). F5 in the world saves it, and so does
-- quitting (src/app/save_store.lua). main.lua and the test harness
-- (tests/support/game_harness.lua) route every LÖVE callback here, so
-- headless tests drive the same path as the app.
--
-- Only the showing screen updates: the world stands still while the
-- builder is open. The builder never touches the world (docs/CONTEXT.md
-- "Builder"), and keeps its draft between visits.
local Session = require("src.game.session")
local WorldGen = require("src.game.world_gen")
local WorldScreen = require("src.app.screens.world")
local BuilderScreen = require("src.app.screens.builder")
local TitleScreen = require("src.app.screens.title")
local DesignStore = require("src.app.design_store")
local SaveStore = require("src.app.save_store")
local StorageFacility = require("src.game.components.storage_facility")

local Flow = {}

local SCREENS = { title = TitleScreen, world = WorldScreen, builder = BuilderScreen }

-- The design library is read once per launch (src/app/design_store.lua)
-- and shared: the builder saves into it, the world places from it.
local function newFlow(config)
	local library, problems = DesignStore.load(config.designs.dir)
	return { config = config, library = library, problems = problems }
end

-- Shows the world of session `ctx`.
local function begin(flow, ctx)
	flow.ctx = ctx
	flow.world = WorldScreen.new(ctx, flow.library)
	flow.builder = BuilderScreen.new(flow.config, flow.library, flow.problems, function()
		return StorageFacility.totals(ctx)
	end)
	flow.screen = "world"
end

-- A flow straight into the world of session `ctx` (tests, which bring their
-- own world).
function Flow.new(ctx, config)
	local flow = newFlow(config)
	begin(flow, ctx)
	return flow
end

-- A flow at launch: the title screen, offering Continue when the save slot
-- holds a world.
function Flow.launch(config)
	local flow = newFlow(config)
	flow.title = TitleScreen.new(SaveStore.exists(config))
	flow.screen = "title"
	return flow
end

-- Starts the session the title screen's choice asks for: the saved one, or
-- a new game (Session.newGame: the starting storage facility and its
-- stockpile) on a new world from config.save.seed. An unreadable save stays on the title
-- with the reason.
local function choose(flow)
	local choice = flow.title.choice
	flow.title.choice = nil
	if choice == "continue" then
		local ctx, reason = SaveStore.load(flow.config)
		if not ctx then
			flow.title.message = "Can't continue: " .. tostring(reason)
			return
		end
		begin(flow, ctx)
	elseif choice == "new" then
		local seed = flow.config.save.seed
		begin(flow, Session.newGame(WorldGen.generate(flow.config, seed), flow.config, seed))
	end
end

-- Saves the session into the slot; true, or nil and why not.
function Flow.save(flow)
	if not flow.ctx then
		return nil, "no session"
	end
	return SaveStore.write(flow.ctx)
end

-- love.quit: autosaves the session, if one is running.
function Flow.quit(flow)
	if flow.ctx then
		Flow.save(flow)
	end
end

-- Calls the showing screen's handler for `event`, if it has one.
local function dispatch(flow, event, ...)
	local module = SCREENS[flow.screen]
	if module[event] then
		module[event](flow[flow.screen], ...)
	end
	if flow.screen == "title" and flow.title.choice then
		choose(flow)
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
	if flow.screen == "world" and WorldScreen.modal(flow.world) then
		dispatch(flow, "keypressed", key)
	elseif flow.screen == "world" and key == "b" then
		flow.screen = "builder"
	elseif flow.screen == "world" and key == "f5" then
		local ok, err = Flow.save(flow)
		flow.world.message = ok and "Saved." or ("Save failed: " .. tostring(err))
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
