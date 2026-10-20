-- E on a port next to the player: walk beside a port, face it, hold E.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local Placement = require("src.game.buildings.placement")
local Inventory = require("src.game.components.inventory")
local Storage = require("src.game.components.storage")

local function brick(shape, x, y, f)
	return { x = x, y = y, z = 0, width = f.width, depth = f.depth, height = 1, shape = shape, rotation = 0, material = "plank", paint = 1, ability = f.ability, port = f.port }
end

local function start()
	_G.love = LoveMock.new()
	local game = GameHarness.startSession(World.new(30, 30))
	local design = { id = "d1", name = "Mill", versions = { { width = 2, depth = 1, bricks = {
		brick("input", 0, 3, { width = 2, depth = 1, port = "input" }),
		brick("output", 4, 3, { width = 2, depth = 1, port = "output" }),
		brick("sawbench", 0, 0, { width = 4, depth = 2, ability = "sawbench" }),
	} } } }
	local b = assert(Placement.build(game.ctx, { design = design, version = 1, facing = "N", tileX = 10, tileY = 10 }))
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
