-- A fishing brick beside water, through the real input path: the design is
-- a real file in love_mock's save directory, placed with a number key and
-- a click; a villager fishes from the shore (never wading in) and hauls take
-- the fish on to storage, for ever.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local Inventory = require("src.game.components.inventory")
local DesignStore = require("src.app.design_store")
local Session = require("src.game.session")
local Load = require("src.game.components.load")

local TILE = Config.tileSize

-- Bricks as the builder saves them: a plank forager on the north row of a 2x1
-- tile baseplate and an output port on its south edge under tile (1, 0).
local FISHER = {
	id = "d2",
	name = "Fisher",
	versions = {
		{
			width = 2,
			depth = 1,
			bricks = {
				{ x = 0, y = 0, z = 0, width = 3, depth = 1, height = 3, shape = "fishing", rotation = 0, material = "plank", paint = 1, ability = "fishing" },
				{ x = 3, y = 3, z = 0, width = 2, depth = 1, height = 1, shape = "output", rotation = 0, material = "plank", paint = 2, port = "output" },
			},
		},
	},
}

-- 20x20 world, character at its centre (px 320, 320) on tile (10, 10), a
-- pond of water within reach of the fishing brick placed at footprint
-- (12..14, 7).
local function launch()
	_G.love = LoveMock.new()
	assert(DesignStore.write(Config.designs.dir, FISHER))
	local world = World.new(20, 20)
	for y = 5, 9 do
		for x = 17, 18 do
			World.setTerrain(world, x, y, "water")
		end
	end
	local game = GameHarness.startSession(world, { storage = Config.stockpile })
	return game, game.ctx.pools.characters[1], world
end

test("a fishing brick's operator fishes from the shore and hauls fish to storage, for ever", function()
	local game, c, world = launch()
	local facility = game.ctx.pools.buildings[1]
	local v = Session.newVillager(1, 5.5 * TILE, 12.5 * TILE, Config)
	table.insert(game.ctx.pools.villagers, v)

	Fake.tap(game, "1")
	Fake.click(game, 1, 640 + (13 * TILE - c.x), 360 + (7.5 * TILE - c.y))
	GameHarness.completeSites(game)
	assert(game.ctx.pools.buildings[2], "the fishing brick was placed")

	local function wet()
		for _, w in ipairs(game.ctx.pools.villagers) do
			if World.terrainAt(world, math.floor(w.x / TILE), math.floor(w.y / TILE)) == "water" then
				return true
			end
		end
	end
	local target = (facility.storage.counts.fish or 0) + 5
	Fake.runUntil(game, function()
		assertEqual(false, wet() or false, "nobody walks onto water")
		return (facility.storage.counts.fish or 0) >= target
	end, 60 * 600)
	assertTrue((facility.storage.counts.fish or 0) >= target, "fish reached storage")
	assertEqual(0, Inventory.count(c.inventory, "fish"), "the player did nothing")
end)
