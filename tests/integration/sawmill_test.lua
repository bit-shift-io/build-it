-- A sawmill through the real input path: the player delivers logs on the
-- input port tile with E, and with no more player action a villager runs
-- the saw bench and haulers take the planks to the storage facility.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local Inventory = require("src.game.components.inventory")
local DesignStore = require("src.app.design_store")
local Session = require("src.game.session")

local TILE = Config.tileSize

local function b(shape, x, y, w, d, extra)
	local r = { x = x, y = y, z = 0, width = w, depth = d, height = 1, shape = shape, rotation = 0, material = "plank", paint = 1 }
	for k, v in pairs(extra) do
		r[k] = v
	end
	return r
end

local SAWMILL = {
	id = "d1",
	name = "Sawmill",
	versions = { { width = 2, depth = 1, bricks = {
		b("sawbench", 0, 0, 4, 2, { ability = "sawbench" }),
		b("input", 0, 3, 2, 1, { port = "input" }),
		b("output", 4, 3, 2, 1, { port = "output" }),
	} } },
}

test("delivered logs become planks a villager makes and haulers store", function()
	_G.love = LoveMock.new()
	assert(DesignStore.write(Config.designs.dir, SAWMILL))
	local game = GameHarness.startSession(World.new(20, 20), { storage = Config.stockpile })
	local input, c = Fake.FakeInput.new(), game.ctx.pools.characters[1]
	Inventory.add(c.inventory, "log", 4)

	Fake.tap(game, "1")
	Fake.click(game, 1, 640 + (13 * TILE - c.x), 360 + (7.5 * TILE - c.y))
	GameHarness.completeSites(game)
	local facility, building = game.ctx.pools.buildings[1], game.ctx.pools.buildings[2]
	assert(building, "the sawmill was placed")
	local inPort = building.ports[1].kind == "input" and building.ports[1] or building.ports[2]

	Fake.holdFor(game, input, "w", 0.3)
	Fake.holdFor(game, input, "d", 0.5)
	assertEqual(inPort, World.portAt(game.ctx.world, math.floor(c.x / TILE), math.floor(c.y / TILE)))
	Fake.holdFor(game, input, "e", 1 / 60)
	assertEqual(4, inPort.buffer.counts.log, "logs delivered")

	local v = Session.newVillager(1, 5.5 * TILE, 12.5 * TILE, Config)
	table.insert(game.ctx.pools.villagers, v)
	local bench = building.functionBricks[1]
	local inside = false
	local planks = facility.storage.counts.plank or 0
	Fake.runUntil(game, function()
		inside = inside or (math.floor(v.x / TILE) == bench.tileX and math.floor(v.y / TILE) == bench.tileY)
		return (facility.storage.counts.plank or 0) >= planks + 2
	end, 60 * 120)
	assertTrue(World.buildingAt(game.ctx.world, bench.tileX, bench.tileY) == building, "the bench's tile is in the footprint")
	assertTrue(inside, "the operator stood on the bench's tile")
	assertEqual(planks + 2, facility.storage.counts.plank, "both planks reached storage")
	assertEqual(nil, inPort.buffer.counts.log, "every log used")
end)
