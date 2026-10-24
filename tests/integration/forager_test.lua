-- A forager beside berry bushes, through the real input path: the design is
-- a real file in love_mock's save directory, placed with a number key and
-- a click; a villager operates it and hauls take the berries on to storage.
-- A picked-clean bush stays and refills.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local Inventory = require("src.game.components.inventory")
local DesignStore = require("src.app.design_store")
local Designs = require("tests.support.designs")
local Session = require("src.game.session")
local Load = require("src.game.components.load")

local TILE = Config.tileSize

-- A forager on the north row of a 2x1 tile floor and an output port on its
-- south edge under tile (1, 0).
local FORAGER = Designs.floor(2, 1, Designs.ability("forager", 0.375, 0.125), Designs.port("output", 1, 1))

-- 20x20 world, character at its centre (px 320, 320) on tile (10, 10),
-- two bushes within reach of the forager placed at footprint (12..13, 7).
local function launch()
	_G.love = LoveMock.new()
	assert(DesignStore.write(Config.designs, "designs", "forager", FORAGER))
	local world = World.new(20, 20)
	for i, x in ipairs({ 11, 14 }) do
		World.addNode(world, { id = i, kind = "bush", tileX = x, tileY = 6, variant = 1, stage = 1, amount = Config.nodes.bush.amount })
	end
	local game = GameHarness.startSession(world, { storage = { plank = 20 } })
	return game, Fake.FakeInput.new(), game.ctx.pools.characters[1], world
end

test("a forager's operator brings berries to storage, and its bushes stay and refill", function()
	local game, _, c, world = launch()
	local facility = game.ctx.pools.buildings[1]
	facility.storage.capacity = 200 -- room for the berries; the tiny test store is full of planks
	local v = Session.newVillager(1, 5.5 * TILE, 12.5 * TILE, Config)
	table.insert(game.ctx.pools.villagers, v)

	Fake.pickDesign(game, "forager")
	Fake.click(game, 1, 640 + (13 * TILE - c.x), 360 + (7.5 * TILE - c.y))
	GameHarness.completeSites(game)
	local b = game.ctx.pools.buildings[2]
	assert(b, "the forager was placed")

	local berries = facility.storage.counts.berry or 0
	local picked = Config.nodes.bush.amount * 2
	Fake.runUntil(game, function()
		return (facility.storage.counts.berry or 0) >= berries + picked
	end, 60 * 300)

	assertEqual(2, #world.nodes, "picked-clean bushes never vanish")
	assertEqual(0, Inventory.count(c.inventory, "berry"), "the player did nothing")
	for _, n in ipairs(world.nodes) do
		assertTrue(n.refilling ~= nil or n.amount > 0, "a clean bush refills")
	end
end)
