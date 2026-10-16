-- A sawmill through the real input path: the player delivers logs on the
-- input port tile with E, waits, and collects planks at the output port.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local Inventory = require("src.game.components.inventory")
local DesignStore = require("src.app.design_store")

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

test("delivered logs become planks the player collects", function()
	_G.love = LoveMock.new()
	assert(DesignStore.write(Config.designs.dir, SAWMILL))
	local game = GameHarness.startSession(World.new(20, 20))
	local input, c = Fake.FakeInput.new(), game.ctx.pools.characters[1]
	Inventory.add(c.inventory, "log", 4)

	Fake.tap(game, "1")
	Fake.click(game, 1, 640 + (13 * TILE - c.x), 360 + (7.5 * TILE - c.y))
	local building = game.ctx.pools.buildings[1]
	assert(building, "the sawmill was placed")
	local inPort, outPort = building.ports[1], building.ports[2]
	if inPort.kind ~= "input" then
		inPort, outPort = outPort, inPort
	end

	Fake.holdFor(game, input, "w", 0.3)
	Fake.holdFor(game, input, "d", 0.5)
	assertEqual(inPort, World.portAt(game.ctx.world, math.floor(c.x / TILE), math.floor(c.y / TILE)))
	local logs = Inventory.count(c.inventory, "log")
	Fake.holdFor(game, input, "e", 1 / 60)
	assertEqual(logs - inPort.buffer.capacity > 0 and logs - inPort.buffer.capacity or 0, Inventory.count(c.inventory, "log"))

	Fake.runUntil(game, function()
		return (outPort.buffer.counts.plank or 0) >= 2
	end, 60 * 60)
	for _ = 1, 60 do -- walk speed varies with the building's aura
		if World.portAt(game.ctx.world, math.floor(c.x / TILE), math.floor(c.y / TILE)) == outPort then
			break
		end
		Fake.holdFor(game, input, "d", 1 / 60)
	end
	assertEqual(outPort, World.portAt(game.ctx.world, math.floor(c.x / TILE), math.floor(c.y / TILE)))
	local before = Inventory.count(c.inventory, "plank")
	Fake.holdFor(game, input, "e", 1 / 60)
	assert(Inventory.count(c.inventory, "plank") >= before + 2, "planks collected")
end)
