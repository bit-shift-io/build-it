-- Harvesting buildings under real LÖVE 12: a saw + pickaxe building beside
-- trees and rocks shows a work line and progress bar per function brick,
-- its output port's fill, and FULL with a red outline once nothing has
-- room. Captures land in tests/screenshots/woodcutter_render_test/.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local Inventory = require("src.game.components.inventory")
local Placement = require("src.game.buildings.placement")
local Session = require("src.game.session")

local function brick(shape, x, y, width, fields)
	local b = { shape = shape, rotation = 0, x = x, y = y, z = 0, width = width, depth = 1, height = 3, material = "plank", paint = 4 }
	for k, v in pairs(fields) do
		b[k] = v
	end
	return b
end

-- 2x1 tiles: a saw and a pickaxe on the north row, an output port on the
-- south edge under tile (1, 0).
local CUTTER = {
	id = "d1",
	name = "Cutter",
	versions = {
		{
			width = 2,
			depth = 1,
			bricks = {
				brick("saw", 0, 0, 3, { ability = "saw" }),
				brick("pickaxe", 4, 0, 3, { ability = "pickaxe" }),
				brick("output", 3, 3, 2, { height = 1, port = "output", paint = 2 }),
			},
		},
	},
}

test("a working building shows its work and fill, and FULL once nothing has room", function()
	local world = World.new(30, 30)
	local id = 0
	local function add(kind, x, y)
		id = id + 1
		World.addNode(world, { id = id, kind = kind, tileX = x, tileY = y, variant = 1 + id % 8, stage = 1, amount = Config.nodes[kind].amount })
	end
	for y = 17, 19 do
		add("tree", 13, y)
		add("rock", 17, y)
	end
	local game = GameHarness.startSession(world, { real = true })
	local ctx, c = game.ctx, game.ctx.pools.characters[1]
	c.inventory = Inventory.new({ plank = 1000, stone = 1000 })
	local b = assert(Placement.build(ctx, { design = CUTTER, version = 1, facing = "N", tileX = 15, tileY = 18 }))
	-- One operator per function brick (docs/adr/0003-function-bricks-need-operators.md).
	for i = 1, 2 do
		table.insert(ctx.pools.villagers, Session.newVillager(i, (14 + i) * Config.tileSize, 22.5 * Config.tileSize, Config))
	end

	Fake.runUntil(game, function()
		return b.functionBricks[1].progress > 1 and b.functionBricks[2].progress > 1
	end, 600)
	assertEqual("working", b.functionBricks[1].state)
	assertEqual("working", b.functionBricks[2].state)
	game:mousemoved(5, 5, 0, 0)
	Capture.capture("working")

	Fake.runUntil(game, function()
		return b.full
	end, 60 * 60)
	-- One operator's load can fill the output on its own, so only some
	-- harvest is guaranteed to be there, not both kinds.
	local counts = b.ports[1].buffer.counts
	assertTrue((counts.log or 0) + (counts.stone or 0) > 0, "harvest in the output")
	Capture.capture("full")
end)
