-- E on a port next to the player: walk beside a port, face it, hold E.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local Placement = require("src.game.buildings.placement")
local Inventory = require("src.game.components.inventory")
local Storage = require("src.game.components.storage")

local Designs = require("tests.support.designs")

local function start()
	_G.love = LoveMock.new()
	local game = GameHarness.startSession(World.new(30, 30))
	-- A 2x1 mill: an input port on the south edge under tile 0, an output
	-- port under tile 1, and a saw bench.
	local design = Designs.floor(2, 1,
		Designs.port("input", 0.25, 1),
		Designs.port("output", 1.25, 1),
		Designs.ability("sawbench", 0.5, 0.25))
	local b = assert(Placement.build(game.ctx, Designs.request(design, "N", 10, 10, "mill", game.ctx.config)))
	local input, output
	for _, p in ipairs(b.ports) do
		if p.kind == "input" then
			input = p
		else
			output = p
		end
	end
	return game, Fake.FakeInput.new(), game.ctx.pools.characters[1], input, output
end

-- Puts the player on the tile south of the port, then nudges it north so
-- it faces the port without reaching it.
local function faceFromSouth(game, input, c, port)
	local tile = Config.tileSize
	c.x, c.y = (port.x + 0.5) * tile, (port.y + 1 + 0.5) * tile
	Fake.holdFor(game, input, "w", 0.05)
	c.y = (port.y + 1 + 0.5) * tile
end

test("holding E facing an output port collects its buffer", function()
	local game, input, c, _, output = start()
	Storage.add(output.buffer, "plank")
	Storage.add(output.buffer, "plank")
	faceFromSouth(game, input, c, output)
	Fake.holdFor(game, input, "e", 0.2)
	assertEqual(2, Inventory.count(c.inventory, "plank"))
	assertEqual(0, Storage.total(output.buffer))
end)

test("holding E facing an input port delivers what it consumes", function()
	local game, input, c, inPort = start()
	Inventory.add(c.inventory, "log", 4)
	Inventory.add(c.inventory, "stone", 1)
	faceFromSouth(game, input, c, inPort)
	Fake.holdFor(game, input, "e", 0.2)
	assertEqual(4, inPort.buffer.counts.log)
	assertEqual(1, Inventory.count(c.inventory, "stone"))
end)
