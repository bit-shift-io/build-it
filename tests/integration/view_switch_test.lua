-- The in-world settings overlay through the real input path: O (or the
-- Settings button) opens it, picking a view switches the running world
-- live and saves the choice. Baking needs a real window, so that part is
-- checked in tests/e2e/view_switch_test.lua.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local Settings = require("src.game.settings")
local SettingsStore = require("src.app.settings_store")
local SettingsScreen = require("src.app.screens.settings")
local Hud = require("src.app.render.hud")

local VIEWS = Settings.views(Config)

local function start()
	_G.love = LoveMock.new()
	local game = GameHarness.startSession({ width = 40, height = 30 })
	return game, Fake.FakeInput.new(), game.ctx.pools.characters[1]
end

test("O opens the overlay showing the current view, and O or Esc closes it", function()
	local game = start()
	Fake.tap(game, "o")
	local overlay = game.flow.world.settings
	assertTrue(overlay ~= nil, "open")
	assertEqual("topdown", overlay.current)
	Fake.tap(game, "o")
	assertEqual(nil, game.flow.world.settings)
	Fake.tap(game, "o")
	Fake.tap(game, "escape")
	assertEqual(nil, game.flow.world.settings)
	assertEqual("world", game.flow.screen)
end)

test("the Settings button opens it, and a click outside the buttons closes it", function()
	local game = start()
	local b = Hud.settingsButton(1280)
	Fake.click(game, 1, b.x + 2, b.y + 2)
	assertTrue(game.flow.world.settings ~= nil, "open")
	Fake.click(game, 1, 5, 700)
	assertEqual(nil, game.flow.world.settings)
end)

test("picking a view switches the live world, keeps the zoom and saves it", function()
	local game = start()
	local world = game.flow.world
	game:wheelmoved(0, 2)
	local zoom = world.camera.zoom
	Fake.tap(game, "o")
	Fake.tap(game, "down")
	Fake.tap(game, "return")
	assertEqual(VIEWS[2], world.view)
	assertEqual(VIEWS[2], game.flow.settings.view)
	assertEqual(nil, world.settings)
	assertEqual(zoom, world.camera.zoom)
	assertEqual(VIEWS[2], SettingsStore.load(game.flow.config).view)
end)

test("picking by click works, and the camera stays on the player", function()
	local game = start()
	local world = game.flow.world
	Fake.tap(game, "o")
	local b = SettingsScreen.buttons(world.settings)[3]
	Fake.click(game, 1, b.x + 5, b.y + 5)
	assertEqual(VIEWS[3], world.view)
	local Projection = require("src.game.projection")
	local p = Projection.new(Config, 1, Config.views[VIEWS[3]])
	local c = game.ctx.pools.characters[1]
	local sx, sy = Projection.worldToScreen(p, c.x / Config.tileSize, c.y / Config.tileSize, 0)
	assertNear(sx, world.camera.x, 0.001)
	assertNear(sy, world.camera.y, 0.001)
end)

test("the session keeps ticking after a switch", function()
	local game, input, c = start()
	Fake.tap(game, "o")
	Fake.tap(game, "down")
	Fake.tap(game, "return")
	local t0, x0 = game.ctx.time, c.x
	Fake.holdFor(game, input, "d", 0.5)
	assertTrue(game.ctx.time > t0, "time advanced")
	assertTrue(c.x > x0, "moved")
end)

test("the first switch to a view asks for a Baking frame", function()
	local game = start()
	Fake.tap(game, "o")
	Fake.tap(game, "down")
	Fake.tap(game, "return")
	assertTrue(game.flow.world.baking, "baking")
end)

test("the overlay is modal: WASD, the picker key and the menu are inert", function()
	local game, input, c = start()
	Fake.tap(game, "o")
	local x0, y0 = c.x, c.y
	Fake.holdFor(game, input, "d", 0.5)
	Fake.holdFor(game, input, "s", 0.5)
	assertEqual(x0, c.x)
	assertEqual(y0, c.y)
	Fake.tap(game, "1")
	assertEqual(nil, game.flow.world.picker)
	Fake.click(game, 2, 300, 300)
	assertEqual(nil, game.flow.world.menu)
	assertEqual(nil, game.flow.world.settings)
end)

test("the overlay opens and closes while paused", function()
	local game = start()
	Fake.tap(game, "p")
	Fake.tap(game, "o")
	assertTrue(game.flow.world.settings ~= nil, "open")
	Fake.tap(game, "down")
	Fake.tap(game, "return")
	assertEqual(VIEWS[2], game.flow.world.view)
	assertTrue(game.flow.world.paused, "still paused")
end)

test("opening the overlay closes the menu and the picker", function()
	local game = start()
	Fake.click(game, 2, 300, 300)
	assertTrue(game.flow.world.menu ~= nil, "menu")
	game.flow.world.menu = nil
	Fake.tap(game, "1")
	assertTrue(game.flow.world.picker ~= nil, "picker")
	Fake.tap(game, "escape")
	Fake.tap(game, "o")
	assertEqual(nil, game.flow.world.picker)
	assertTrue(game.flow.world.settings ~= nil, "settings")
end)
