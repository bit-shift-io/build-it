-- Settings through the real input path: open Settings from the title, pick
-- a view by key or click, relaunch over the same save directory.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local Settings = require("src.game.settings")
local SettingsScreen = require("src.app.screens.settings")
local SaveCodec = require("src.game.save.codec")

local function launch(saveDir)
	_G.love = LoveMock.new({ saveDir = saveDir })
	return GameHarness.launch()
end

-- Title with no save: New game, Settings.
local function openSettings(game)
	Fake.tap(game, "down")
	Fake.tap(game, "return")
	assertEqual("settingsScreen", game.flow.screen)
end

test("Settings opens from the title and Esc returns", function()
	local game = launch()
	assertEqual("topdown", game.flow.settings.view)
	openSettings(game)
	Fake.tap(game, "escape")
	assertEqual("title", game.flow.screen)
end)

test("a key picks a view, marks it, and a relaunch keeps it", function()
	local game = launch()
	local dir = love.filesystem.getSaveDirectory()
	openSettings(game)
	assertEqual(1, game.flow.settingsScreen.selected)
	Fake.tap(game, "down")
	Fake.tap(game, "return")
	local picked = Settings.views(Config)[2]
	assertEqual(picked, game.flow.settings.view)
	assertEqual(picked, game.flow.settingsScreen.current)

	local again = launch(dir)
	assertEqual(picked, again.flow.settings.view)
	openSettings(again)
	assertEqual(2, again.flow.settingsScreen.selected)
end)

test("a click picks a view", function()
	local game = launch()
	openSettings(game)
	local b = SettingsScreen.buttons(game.flow.settingsScreen)[3]
	Fake.click(game, 1, b.x + 5, b.y + 5)
	assertEqual(Settings.views(Config)[3], game.flow.settings.view)
end)

test("a corrupt settings file loads the defaults", function()
	local game = launch()
	local dir = love.filesystem.getSaveDirectory()
	love.filesystem.write(Config.settings.file, "\0\1not settings")
	local again = launch(dir)
	assertEqual("topdown", again.flow.settings.view)
end)

test("the view is shared by new games and kept out of the world save", function()
	local game = launch()
	local dir = love.filesystem.getSaveDirectory()
	openSettings(game)
	Fake.tap(game, "down")
	Fake.tap(game, "return")
	Fake.tap(game, "escape")
	Fake.tap(game, "up")
	Fake.tap(game, "return") -- New game
	assertEqual("world", game.flow.screen)
	assertEqual(Settings.views(Config)[2], game.flow.settings.view)
	assertTrue(game:quit() == nil)
	local text = love.filesystem.read(Config.save.file)
	assertTrue(text ~= nil, "fixture: world saved on quit")
	assertTrue(not text:find(Settings.views(Config)[2], 1, true), "save mentions the view")
end)
