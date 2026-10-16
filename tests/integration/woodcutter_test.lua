-- A woodcutter beside a forest, through the real input path: the design is
-- a real file in love_mock's save directory, placed with a number key and
-- a click; its saw fills the output port; the player walks onto the port
-- tile and holds E to collect the logs.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local Inventory = require("src.game.components.inventory")
local DesignStore = require("src.app.design_store")

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
	local game = GameHarness.startSession(world)
	return game, Fake.FakeInput.new(), game.ctx.pools.characters[1], world
end

test("a woodcutter beside a forest fills its output, and the player collects the logs", function()
	local game, input, c, world = launch()

	-- Footprint (12..13, 7); the ghost centres on the pointer.
	Fake.tap(game, "1")
	Fake.click(game, 1, 640 + (13 * TILE - c.x), 360 + (7.5 * TILE - c.y))
	local b = game.ctx.pools.buildings[1]
	assert(b, "the woodcutter was placed")
	local port = b.ports[1]
	assertEqual(13, port.x)
	assertEqual(8, port.y)

	Fake.runUntil(game, function()
		return b.full
	end, 60 * 60)
	local logs = port.buffer.counts.log
	assertEqual(port.buffer.capacity, logs, "the output port is full of logs")

	local before = Inventory.count(c.inventory, "log")
	Fake.holdFor(game, input, "w", 0.3) -- up onto row 8
	Fake.holdFor(game, input, "d", 0.7) -- east onto the port tile
	assertEqual(port, World.portAt(world, math.floor(c.x / TILE), math.floor(c.y / TILE)), "standing on the port")
	Fake.holdFor(game, input, "e", 1 / 60)

	assertEqual(before + logs, Inventory.count(c.inventory, "log"))
	assertEqual(nil, port.buffer.counts.log, "the output is empty")
	assertFalse(b.full, "the woodcutter resumes")
end)
