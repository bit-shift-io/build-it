-- Team colours through the real input path (docs/CONTEXT.md "Team
-- palette", "Settings"): picking a primary or secondary colour in Settings
-- (the in-world overlay or the title's screen) stores it, outlives a
-- relaunch, and the world draws buildings in the new palette, so a
-- `color = "primary"` roof's sprites rebake in the new colour (the sprite
-- key holds the palette). The pixels themselves are e2e.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Designs = require("tests.support.designs")
local Config = require("src.game.config")
local Placement = require("src.game.buildings.placement")
local Palette = require("src.game.palette")
local WorldScreen = require("src.app.screens.world")
local SettingsScreen = require("src.app.screens.settings")
local ColourPicker = require("src.app.ui.colour_picker")
local DesignCache = require("src.app.bake.design_cache")
local Baker = require("src.app.bake.baker")

local HUT = Designs.floor(1, 1, 'box{ id = "roof", color = "primary", size = { 1, 1, 0.5 }, transform = { move = { 0, 0, 0.0625 } } }')

-- Clicks the settings screen's `field` ("primary" or "secondary") swatch
-- number `n`; returns its colour.
local function clickColour(game, screen, field, n)
	local seen = 0
	for _, swatch in ipairs(SettingsScreen.colourPicker(screen).swatches) do
		if swatch.section == field then
			seen = seen + 1
			if seen == n then
				Fake.click(game, 1, swatch.x + swatch.width / 2, swatch.y + swatch.height / 2)
				return swatch.color
			end
		end
	end
	error("no " .. field .. " swatch " .. n)
end

-- The roof's colour as baked with `palette`.
local function roofColour(blueprint, palette)
	for _, v in ipairs(blueprint.mesh) do
		if v.slot == "primary" then
			return { Baker.color(v, palette) }
		end
	end
	error("fixture: the roof has primary vertices")
end

test("a new primary colour in the world's Settings recolours a primary roof and outlives a relaunch", function()
	_G.love = LoveMock.new()
	local game = GameHarness.startSession({ width = 20, height = 20 })
	local hut = Placement.build(game.ctx, Designs.request(HUT, "N", 5, 5))
	local world = game.flow.world
	local before = WorldScreen.palette(world)
	assertEqual(Palette.DEFAULT_PRIMARY[1], roofColour(hut.blueprint, before)[1])

	Fake.tap(game, "o")
	local green = clickColour(game, world.settings, "primary", 4)
	assertEqual(ColourPicker.PRESETS[4], green)
	assertTrue(world.settings ~= nil, "the overlay stays open")
	assertEqual(green[2], game.flow.settings.primary[2])

	local after = WorldScreen.palette(world)
	local roof = roofColour(hut.blueprint, after)
	assertEqual(green[1], roof[1])
	assertEqual(green[2], roof[2])
	assertTrue(DesignCache.key(hut.blueprint, 1, world.view, before) ~= DesignCache.key(hut.blueprint, 1, world.view, after), "the sprite rebakes")
	assertEqual(Palette.DEFAULT_SECONDARY[3], after.secondary[3], "secondary untouched")

	local dir = love.filesystem.getSaveDirectory()
	_G.love = LoveMock.new({ saveDir = dir })
	local again = GameHarness.launch({ config = game.flow.config })
	assertEqual(green[2], again.flow.settings.primary[2])
end)

test("a secondary colour picked on the title's Settings colours the new game, never its save", function()
	_G.love = LoveMock.new()
	local game = GameHarness.launch()
	Fake.tap(game, "down")
	Fake.tap(game, "return")
	assertEqual("settingsScreen", game.flow.screen)
	local picked = clickColour(game, game.flow.settingsScreen, "secondary", 12)
	assertEqual(picked[1], game.flow.settings.secondary[1])
	Fake.tap(game, "escape")
	Fake.tap(game, "up")
	Fake.tap(game, "return") -- New game
	assertEqual("world", game.flow.screen)
	assertEqual(picked[1], WorldScreen.palette(game.flow.world).secondary[1])
	game:quit()
	local text = assert(love.filesystem.read(Config.save.file))
	assertTrue(not text:find("secondary", 1, true), "the world save holds no team colour")
end)
