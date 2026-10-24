-- App flow (title -> Settings picks the view): which screen is showing, and the switch between them. The app
-- launches on the title screen (Continue / New game); B opens the script
-- builder from the world; Esc goes back (unless a builder menu or text
-- box is open, when Esc only closes it). F5 in the world saves it, and so
-- does quitting (src/app/save_store.lua). main.lua and the test harness
-- (tests/support/game_harness.lua) route every LÖVE callback here, so
-- headless tests drive the same path as the app.
--
-- Only the showing screen updates: the world stands still while the
-- builder is open. The builder never touches the world (docs/CONTEXT.md
-- "Builder").
local Session = require("src.game.session")
local WorldGen = require("src.game.world_gen")
local WorldScreen = require("src.app.screens.world")
local ScriptBuilderScreen = require("src.app.screens.script_builder")
local TitleScreen = require("src.app.screens.title")
local DesignStore = require("src.app.design_store")
local SaveStore = require("src.app.save_store")
local SettingsStore = require("src.app.settings_store")
local SettingsScreen = require("src.app.screens.settings")
local Builtins = require("src.game.designs.builtins")
local Library = require("src.game.designs.library")
local Settings = require("src.game.settings")

local Flow = {}

local SCREENS = {
	title = TitleScreen,
	world = WorldScreen,
	scriptBuilder = ScriptBuilderScreen,
	settingsScreen = SettingsScreen,
}

local function newFlow(config)
	-- SDL3 (LÖVE 12) starts with text input off: no love.textinput, so the
	-- picker search, the builder's text boxes and code panel get no typing.
	love.keyboard.setTextInput(true)
	-- The built-in design scripts (src/game/designs/builtins.lua), read once
	-- per launch; they ship with the game, so a missing one is a bug.
	local builtins = assert(Builtins.load(function(path)
		return love.filesystem.read(path)
	end))
	-- The player's settings (src/game/settings.lua), read once per launch.
	return {
		config = config,
		builtins = builtins,
		settings = SettingsStore.load(config),
	}
end

-- The design library as it is now (src/game/designs/library.lua): the
-- built-ins with the player's saved scripts (src/app/design_store.lua)
-- shadowing them, read afresh so a file written by hand shows.
function Flow.library(flow)
	return Library.merge(flow.builtins, DesignStore.load(flow.config.designs))
end

-- Shows the world of session `ctx`.
local function begin(flow, ctx)
	flow.ctx = ctx
	flow.world = WorldScreen.new(ctx, function()
		return Flow.library(flow)
	end, flow.settings.view, flow.settings)
	flow.scriptBuilder = ScriptBuilderScreen.new(flow.config, function(path)
		return love.filesystem.read(path)
	end, function()
		return Flow.library(flow)
	end, function()
		return Settings.palette(flow.settings)
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
-- a new game (Session.newGame: the starting storage facility, compiled from
-- the design library, and its stockpile) on a new world from
-- config.save.seed. An unreadable save stays on the title
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
	elseif choice == "settings" then
		flow.settingsScreen = SettingsScreen.new(flow.config, flow.settings.view, flow.settings)
		flow.screen = "settingsScreen"
	elseif choice == "new" then
		local seed = flow.config.save.seed
		begin(flow, Session.newGame(WorldGen.generate(flow.config, seed), flow.config, seed, Flow.library(flow)))
	end
end

-- Stores team colour `picked` ({ field, color }, a Settings screen's
-- colourChoice), in the flow and on disk.
local function pickColour(flow, picked)
	flow.settings[picked.field] = { picked.color[1], picked.color[2], picked.color[3] }
	SettingsStore.write(flow.config, flow.settings)
end

-- Stores the view the settings screen picked, in the flow and on disk.
local function pick(flow)
	local screen = flow.settingsScreen
	flow.settings.view = screen.choice
	screen.choice = nil
	screen.current = flow.settings.view
	SettingsStore.write(flow.config, flow.settings)
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
	elseif flow.screen == "settingsScreen" and flow.settingsScreen.choice then
		pick(flow)
	elseif flow.screen == "settingsScreen" and flow.settingsScreen.colourChoice then
		pickColour(flow, flow.settingsScreen.colourChoice)
		flow.settingsScreen.colourChoice = nil
	elseif flow.screen == "world" and flow.world.colourChoice then
		-- The in-world overlay picked a team colour: save it like the title's.
		pickColour(flow, flow.world.colourChoice)
		flow.world.colourChoice = nil
	elseif flow.screen == "world" and flow.world.viewChoice then
		-- The in-world overlay switched the view: save it like the title's.
		flow.settings.view = flow.world.viewChoice
		flow.world.viewChoice = nil
		SettingsStore.write(flow.config, flow.settings)
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
		-- Reread on every open, so edits to the file show.
		ScriptBuilderScreen.open(flow.scriptBuilder)
		flow.screen = "scriptBuilder"
	elseif flow.screen == "world" and key == "f5" then
		local ok, err = Flow.save(flow)
		flow.world.message = ok and "Saved." or ("Save failed: " .. tostring(err))
	elseif flow.screen == "settingsScreen" and key == "escape" then
		flow.screen = "title"
	elseif flow.screen == "scriptBuilder" and key == "escape" and not ScriptBuilderScreen.modal(flow.scriptBuilder) then
		flow.screen = "world"
		WorldScreen.refresh(flow.world) -- the builder may have changed designs
	else
		dispatch(flow, "keypressed", key)
	end
end

-- Typed text (love.textinput), e.g. the picker's search.
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
