-- The in-world settings overlay under real LÖVE 12: switching topdown ->
-- iso2to1 -> iso -> topdown draws each view, the first switch to a view
-- shows a "Baking..." frame and bakes on the next, and returning to a view
-- already drawn bakes nothing. Captures land in
-- tests/screenshots/view_switch_test/.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local WorldGen = require("src.game.world_gen")
local Baker = require("src.app.bake.baker")
local Settings = require("src.game.settings")
local SettingsScreen = require("src.app.screens.settings")

local CACHE_DIR = "e2e_props_view_switch"

local config = {}
for k, v in pairs(Config) do
	config[k] = v
end
config.props = { variants = Config.props.variants, seed = Config.props.seed, cacheDir = CACHE_DIR }

for _, name in ipairs(love.filesystem.getDirectoryItems(CACHE_DIR)) do
	love.filesystem.remove(CACHE_DIR .. "/" .. name)
end

local game = GameHarness.startSession(WorldGen.generate(config, 1), {
	real = true,
	config = config,
	seed = 1,
	storage = { plank = 2 },
})

-- Counts Baker.bake and Baker.bakeTurned calls (passing through) for the rest
-- of the file. Props bake through bakeTurned.
local bakes = 0
for _, name in ipairs({ "bake", "bakeTurned" }) do
	local real = Baker[name]
	Baker[name] = function(...)
		bakes = bakes + 1
		return real(...)
	end
end

-- Opens the overlay and clicks `view`'s button.
local function switchTo(view)
	Fake.tap(game, "o")
	local screen = game.flow.world.settings
	for i, name in ipairs(Settings.views(config)) do
		if name == view then
			local b = SettingsScreen.buttons(screen)[i]
			Fake.click(game, 1, b.x + 5, b.y + 5)
		end
	end
	assertEqual(view, game.flow.world.view)
end

test("the first switch to a view shows a Baking frame, then bakes on the next draw", function()
	Capture.capture("topdown")
	local before = bakes
	local zoom = game.flow.world.camera.zoom
	switchTo("iso2to1")
	Capture.capture("iso2to1_baking_frame")
	assertEqual(before, bakes, "the Baking frame bakes nothing")
	Capture.capture("iso2to1")
	assertTrue(bakes > before, "the next draw bakes the view")
	assertEqual(zoom, game.flow.world.camera.zoom)
end)

test("a second new view bakes the same way", function()
	local before = bakes
	switchTo("iso")
	Capture.capture("iso_baking_frame")
	assertEqual(before, bakes)
	Capture.capture("iso")
	assertTrue(bakes > before, "baked")
end)

test("returning to a drawn view shows no Baking frame and bakes nothing new", function()
	local before = bakes
	for _, view in ipairs({ "topdown", "iso2to1", "iso", "topdown" }) do
		switchTo(view)
		assertFalse(game.flow.world.baking, "no Baking frame for " .. view)
		Capture.capture("again_" .. view)
	end
	assertEqual(before, bakes, "no new bakes")
end)

test("the switch is saved", function()
	assertEqual("topdown", game.flow.settings.view)
end)
