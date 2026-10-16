-- Function bricks in placed buildings (docs/CONTEXT.md "Function brick"):
-- each saw or pickaxe reserves a node within reach and harvests it, in
-- parallel with the others, into storage and output buffers.
local Session = require("src.game.session")
local World = require("src.game.world")
local Config = require("src.game.config")
local Placement = require("src.game.buildings.placement")
local Inventory = require("src.game.components.inventory")
local FunctionBrick = require("src.game.components.function_brick")
local Ports = require("src.game.components.ports")

local STEP = 1 / 60

-- A brick record as the builder saves it (src/game/builder/draft.lua).
local function brick(shape, x, y, z, material)
	local fields = {
		saw = { width = 3, depth = 1, height = 3, ability = "saw" },
		pickaxe = { width = 3, depth = 1, height = 3, ability = "pickaxe" },
		output = { width = 2, depth = 1, height = 1, port = "output" },
		storage = { width = 2, depth = 2, height = 2, storage = 8 },
		["1x1"] = { width = 1, depth = 1, height = 1 },
	}
	local f = fields[shape]
	return {
		x = x,
		y = y,
		z = z,
		width = f.width,
		depth = f.depth,
		height = f.height,
		shape = shape,
		rotation = 0,
		material = material or "plank",
		paint = 1,
		ability = f.ability,
		port = f.port,
		storage = f.storage,
	}
end

-- A 2x1 tile design (8x4 studs): `first` and `second` (shape names, or nil
-- for a plain 1x1 plank filler, so trait totals match) on the north row,
-- and an output port on the south edge facing the tile below tile (1, 0).
local function design(first, second, extra)
	local bricks = {
		brick(first, 0, 0, 0),
		second and brick(second, 4, 0, 0) or brick("1x1", 4, 0, 0),
		brick("output", 3, 3, 0),
	}
	for _, b in ipairs(extra or {}) do
		table.insert(bricks, b)
	end
	return { id = "d1", name = "Cutter", versions = { { width = 2, depth = 1, bricks = bricks } } }
end

local function newSession(config)
	local ctx = Session.new(World.new(30, 30), config or Config, 1)
	return ctx, ctx.pools.characters[1]
end

-- Places `d` facing N with its north-west tile on (x, y), paid for.
local function build(ctx, c, d, x, y)
	c.inventory = Inventory.new({ plank = 10000, stone = 10000 })
	return assert(Placement.place(ctx, c, { design = d, version = 1, facing = "N", tileX = x, tileY = y }))
end

local nextId = 0
local function node(ctx, kind, x, y)
	nextId = nextId + 1
	return World.addNode(ctx.world, {
		id = nextId,
		kind = kind,
		tileX = x,
		tileY = y,
		variant = 1,
		stage = 1,
		amount = Config.nodes[kind].amount,
	})
end

local function run(ctx, seconds)
	for _ = 1, math.floor(seconds / STEP + 0.5) do
		Session.advance(ctx, STEP)
	end
end

local function output(building)
	return building.ports[1].buffer.counts
end

test("a saw beside a tree puts a log in the output buffer after one cycle", function()
	local ctx, c = newSession()
	local b = build(ctx, c, design("saw"), 10, 10)
	node(ctx, "tree", 9, 10)

	local cycle = FunctionBrick.cycle(b.traits, Config)
	run(ctx, cycle * 0.9)
	assertEqual(nil, output(b).log)
	run(ctx, cycle * 0.2)
	assertEqual(1, output(b).log)
end)

test("two saws reserve and harvest two different trees at once", function()
	local ctx, c = newSession()
	local b = build(ctx, c, design("saw", "saw"), 10, 10)
	local west = node(ctx, "tree", 9, 10)
	local east = node(ctx, "tree", 12, 10)

	run(ctx, FunctionBrick.cycle(b.traits, Config) + STEP)

	local first, second = b.functionBricks[1], b.functionBricks[2]
	assertTrue(first.node ~= nil and second.node ~= nil, "both saws hold a node")
	assertTrue(first.node ~= second.node, "different nodes")
	assertEqual(Config.nodes.tree.amount - 1, west.amount)
	assertEqual(Config.nodes.tree.amount - 1, east.amount)
	assertEqual(2, output(b).log)
end)

-- Logs collected from a building's output over `seconds`, emptying it every
-- step so it never fills.
local function yield(d, seconds)
	local ctx, c = newSession()
	local b = build(ctx, c, d, 10, 10)
	for y = 7, 14 do
		node(ctx, "tree", 8, y)
		node(ctx, "tree", 13, y)
	end
	local got = 0
	for _ = 1, math.floor(seconds / STEP + 0.5) do
		Session.advance(ctx, STEP)
		for item, n in pairs(output(b)) do
			got = got + n
			output(b)[item] = nil
		end
	end
	return got
end

test("a 2-saw woodcutter yields logs at twice the rate of a 1-saw woodcutter", function()
	local one = yield(design("saw"), 60)
	local two = yield(design("saw", "saw"), 60)
	assertTrue(one > 5, "the 1-saw cutter works: " .. one)
	assertEqual(2 * one, two)
end)

test("a saw and a pickaxe building yields both logs and stone", function()
	local ctx, c = newSession()
	local b = build(ctx, c, design("saw", "pickaxe"), 10, 10)
	node(ctx, "tree", 9, 10)
	node(ctx, "rock", 12, 10)

	run(ctx, FunctionBrick.cycle(b.traits, Config) + STEP)

	assertEqual(1, output(b).log)
	assertEqual(1, output(b).stone)
end)

test("a node beyond the building's reach is never harvested", function()
	local ctx, c = newSession()
	local b = build(ctx, c, design("saw"), 10, 10)
	local r = FunctionBrick.reach(b.traits, Config)
	local far = node(ctx, "tree", 10 - r - 1, 10)

	run(ctx, FunctionBrick.cycle(b.traits, Config) * 3)

	assertEqual(Config.nodes.tree.amount, far.amount)
	assertEqual("idle", b.functionBricks[1].state)
	local near = node(ctx, "tree", 10 - r, 10 + r)
	run(ctx, FunctionBrick.cycle(b.traits, Config) + STEP)
	assertEqual(Config.nodes.tree.amount - 1, near.amount, "a node at reach, diagonally, is harvested")
end)

test("a full output stalls the saw, and it resumes when the player collects", function()
	local ctx, c = newSession()
	local b = build(ctx, c, design("saw"), 10, 10)
	local tree = node(ctx, "tree", 9, 10)
	local size = b.ports[1].buffer.capacity
	local cycle = FunctionBrick.cycle(b.traits, Config)

	run(ctx, cycle * (size + 3))

	assertEqual(size, output(b).log)
	assertEqual(Config.nodes.tree.amount - size, tree.amount, "nothing harvested while full")
	assertEqual("full", b.functionBricks[1].state)
	assertTrue(b.full, "the building shows it is full")

	Ports.collect(b.ports[1], c.inventory)
	run(ctx, STEP)
	assertFalse(b.full)
	assertEqual("working", b.functionBricks[1].state)
	run(ctx, cycle)
	assertEqual(1, output(b).log)
end)

test("storage fills first and drains into the output as it frees", function()
	local ctx, c = newSession()
	local d = design("saw", nil, { brick("storage", 0, 1, 0) })
	local b = build(ctx, c, d, 10, 10)
	node(ctx, "tree", 9, 10)
	node(ctx, "tree", 9, 11)
	local stored = b.storage.capacity
	local size = b.ports[1].buffer.capacity
	assertTrue(stored >= 8, "storage bricks add storage")

	run(ctx, FunctionBrick.cycle(b.traits, Config) * (stored + size + 2))

	assertEqual(size, output(b).log)
	assertEqual(stored, b.storage.counts.log)
	assertTrue(b.full)
	Ports.collect(b.ports[1], c.inventory)
	run(ctx, STEP)
	assertEqual(size, output(b).log, "storage refills the output")
	assertEqual(stored - size, b.storage.counts.log)
end)

test("productivity shortens the cycle and negative productivity lengthens it", function()
	local base = FunctionBrick.cycle({ productivity = 0 }, Config)
	assertEqual(Config.production.harvestCycle, base)
	assertTrue(FunctionBrick.cycle({ productivity = 10 }, Config) < base)
	assertTrue(FunctionBrick.cycle({ productivity = -10 }, Config) > base)
	local slowest = Config.production.harvestCycle / Config.production.minSpeed
	assertEqual(slowest, FunctionBrick.cycle({ productivity = -1000 }, Config))
end)

test("a building with more productivity harvests faster", function()
	local plain = yield(design("saw"), 30)
	local extra = {}
	for i = 0, 7 do
		table.insert(extra, brick("1x1", i, 2, 0))
		table.insert(extra, brick("1x1", i, 1, 0))
	end
	local productive = yield(design("saw", nil, extra), 30)
	assertTrue(productive > plain, productive .. " > " .. plain)
end)

test("harvest intent on an output port tile collects its items instead of hand-harvesting", function()
	local ctx, c = newSession()
	local b = build(ctx, c, design("saw"), 10, 10)
	local tree = node(ctx, "tree", 9, 10)
	run(ctx, FunctionBrick.cycle(b.traits, Config) * 2 + STEP)
	local amount = tree.amount
	assertEqual(2, output(b).log)

	local port = b.ports[1]
	local tile = Config.tileSize
	c.x, c.y = (port.x + 0.5) * tile, (port.y + 0.5) * tile
	local roadside = node(ctx, "tree", port.x - 1, port.y)
	ctx.intents[1] = { x = 0, y = 0, harvest = true }
	Session.advance(ctx, STEP)
	ctx.intents[1] = nil

	assertEqual(2, Inventory.count(c.inventory, "log"))
	assertEqual(nil, output(b).log)
	assertEqual(Config.nodes.tree.amount, roadside.amount, "no hand harvest while collecting")
	assertEqual(amount, tree.amount)
end)
