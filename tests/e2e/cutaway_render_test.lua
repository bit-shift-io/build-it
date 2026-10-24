-- The cutaway under real LÖVE 12 (docs/CONTEXT.md "Cutaway"): the player
-- walks in through a storage facility's south doorway and that building
-- draws cut at half body height, showing its interior, a villager inside
-- and the cut walls, while a second facility beside it stays whole.
-- Walking out restores the full sprite. Captures land in
-- tests/screenshots/cutaway_render_test/.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local Inventory = require("src.game.components.inventory")
local Placement = require("src.game.buildings.placement")
local Session = require("src.game.session")
local BuildingsRender = require("src.app.render.buildings")
local Designs = require("tests.support.designs")

local TILE = Config.tileSize

-- Its own prop cache folder, so the test never reads or writes the
-- player's (docs/memory/e2e-isolate-save-dir.md).
local function testConfig()
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.props = { variants = Config.props.variants, seed = Config.props.seed, cacheDir = "e2e_cutaway_props" }
	return config
end

test("the building the player walks into draws cut away, and whole again once out", function()
	local config = testConfig()
	for _, name in ipairs(love.filesystem.getDirectoryItems(config.props.cacheDir)) do
		love.filesystem.remove(config.props.cacheDir .. "/" .. name)
	end
	local source = assert(love.filesystem.read("content/designs/storage_facility.lua"))

	-- 30x30 world, the character at its centre, px (480, 480). Facility A
	-- on tiles 14..16 x 12..13: its doorway spans x 14.25..15.25 tiles,
	-- right above the character. Facility B beside it on 18..20 x 12..13.
	local world = World.new(30, 30)
	local game = GameHarness.startSession(world, { real = true, config = config })
	local ctx, c = game.ctx, game.ctx.pools.characters[1]
	c.inventory = Inventory.new({ plank = 1000, stone = 1000 })
	local a = assert(Placement.build(ctx, Designs.request(source, "N", 14, 12, "facility_a", ctx.config)))
	assert(Placement.build(ctx, Designs.request(source, "N", 18, 12, "facility_b", ctx.config)))
	assertEqual(nil, BuildingsRender.cutawayOf(ctx), "outside, nothing is cut away")
	game:mousemoved(5, 5, 0, 0)
	Capture.capture("outside")

	local input = Fake.FakeInput.new()
	Fake.holdFor(game, input, "w", 1)
	assertTrue(c.y < 14 * TILE and c.y > 12 * TILE, "the player walked in through the doorway")
	assertEqual(a, BuildingsRender.cutawayOf(ctx), "the building the player stands in is cut away")
	-- A villager inside the cut building, beside the player.
	table.insert(ctx.pools.villagers, Session.newVillager(1, c.x - 0.5 * TILE, c.y, ctx.config))
	Fake.runUntil(game, function()
		return true
	end, 1)
	Capture.capture("inside")

	Fake.holdFor(game, input, "s", 1)
	assertTrue(c.y > 14 * TILE, "the player walked back out")
	assertEqual(nil, BuildingsRender.cutawayOf(ctx), "leaving restores the full sprite")
	Capture.capture("left")
end)
