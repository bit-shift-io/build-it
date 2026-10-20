-- A woodcutter beside a forest, through the real input path: the design is
-- a real file in love_mock's save directory, placed with a number key and
-- a click; a villager operates its saw and hauls take the logs on to storage.
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

-- Bricks as the builder saves them: a plank saw on the north row of a 2x1
-- tile baseplate and an output port on its south edge under tile (1, 0).
local WOODCUTTER = {
	id = "d1",
	name = "Woodcutter",
	versions = {
		{
			width = 2,
			depth = 1,
			bricks = {
				{ x = 0, y = 0, z = 0, width = 3, depth = 1, height = 3, shape = "saw", rotation = 0, material = "plank", paint = 1, ability = "saw" },
				{ x = 3, y = 3, z = 0, width = 2, depth = 1, height = 1, shape = "output", rotation = 0, material = "plank", paint = 2, port = "output" },
			},
		},
	},
}

-- 20x20 world, character at its centre (px 320, 320) on tile (10, 10),
-- trees in columns 11 and 14, rows 4..6.
local function launch()
	_G.love = LoveMock.new()
	assert(DesignStore.write(Config.designs.dir, WOODCUTTER))
	local world = World.new(20, 20)
	local id = 0
	for y = 4, 6 do
		for _, x in ipairs({ 11, 14 }) do
			id = id + 1
			World.addNode(world, { id = id, kind = "tree", tileX = x, tileY = y, variant = 1, stage = 1, amount = Config.nodes.tree.amount })
		end
	end
	local game = GameHarness.startSession(world, { storage = Config.stockpile })
	return game, Fake.FakeInput.new(), game.ctx.pools.characters[1], world
end

test("a woodcutter beside a forest is run by a villager and logs reach storage with no player action", function()
	local game, input, c = launch()
	local facility = game.ctx.pools.buildings[1]
	local v = Session.newVillager(1, 5.5 * TILE, 12.5 * TILE, Config)
	table.insert(game.ctx.pools.villagers, v)

	-- Footprint (12..13, 7); the ghost centres on the pointer.
	Fake.tap(game, "1")
	Fake.tap(game, "return")
	Fake.click(game, 1, 640 + (13 * TILE - c.x), 360 + (7.5 * TILE - c.y))
	GameHarness.completeSites(game)
	local b = game.ctx.pools.buildings[2] -- after the storage facility
	assert(b, "the woodcutter was placed")
	local port = b.ports[1]
	assertEqual(13, port.x)
	assertEqual(8, port.y)

	local logs = facility.storage.counts.log or 0
	Fake.runUntil(game, function()
		return (facility.storage.counts.log or 0) >= logs + 8
	end, 60 * 120)

	assertTrue(v.job ~= nil or Load.empty(v.load) or v.load.item == "log", "the villager works the saw")
	assertEqual(0, Inventory.count(c.inventory, "log"), "the player did nothing")
end)

test("a woodcutter with no villager harvests nothing", function()
	local game, _, c = launch()
	Fake.tap(game, "1")
	Fake.tap(game, "return")
	Fake.click(game, 1, 640 + (13 * TILE - c.x), 360 + (7.5 * TILE - c.y))
	GameHarness.completeSites(game)
	local b = game.ctx.pools.buildings[2]
	assert(b, "the woodcutter was placed")

	local frames = 0
	Fake.runUntil(game, function()
		frames = frames + 1
		return frames >= 600
	end, 700)

	assertEqual(nil, b.ports[1].buffer.counts.log)
end)
