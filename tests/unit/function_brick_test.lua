-- Harvesting function bricks in placed buildings (docs/CONTEXT.md "Function
-- brick", "Operator job"): a saw or pickaxe runs only while a villager holds
-- its operator job; the operator reserves a node within reach, harvests it
-- into their load and carries the load to an output port.
local Session = require("src.game.session")
local World = require("src.game.world")
local Config = require("src.game.config")
local Placement = require("src.game.buildings.placement")
local Inventory = require("src.game.components.inventory")
local FunctionBrick = require("src.game.components.function_brick")
local Ports = require("src.game.components.ports")
local Load = require("src.game.components.load")

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
	return assert(Placement.build(ctx, { design = d, version = 1, facing = "N", tileX = x, tileY = y }))
end

local TILE = Config.tileSize

local nextId = 0
local function node(ctx, kind, x, y, amount)
	nextId = nextId + 1
	return World.addNode(ctx.world, {
		id = nextId,
		kind = kind,
		tileX = x,
		tileY = y,
		variant = 1,
		stage = 1,
		amount = amount or Config.nodes[kind].amount,
	})
end

local nextVillager = 0
local function villager(ctx, tx, ty)
	nextVillager = nextVillager + 1
	local v = Session.newVillager(nextVillager, (tx or 6) + 0.5, (ty or 6) + 0.5, Config)
	v.x, v.y = ((tx or 6) + 0.5) * TILE, ((ty or 6) + 0.5) * TILE
	table.insert(ctx.pools.villagers, v)
	return v
end

local function run(ctx, seconds)
	for _ = 1, math.floor(seconds / STEP + 0.5) do
		Session.advance(ctx, STEP)
	end
end

local function output(building)
	return building.ports[1].buffer.counts
end

test("a saw with no villager harvests nothing", function()
	local ctx, c = newSession()
	local b = build(ctx, c, design("saw"), 10, 10)
	local tree = node(ctx, "tree", 9, 10)

	run(ctx, FunctionBrick.cycle(b.traits, Config) * 3)

	assertEqual(Config.nodes.tree.amount, tree.amount)
	assertEqual(nil, output(b).log)
	assertEqual(nil, b.functionBricks[1].node)
end)

test("an operator fills a load to the limit across two trees, then delivers it to the output", function()
	local ctx, c = newSession()
	local b = build(ctx, c, design("saw"), 10, 10)
	local west = node(ctx, "tree", 9, 10, 2)
	local east = node(ctx, "tree", 12, 10, 2)
	local v = villager(ctx)

	local seen = 0
	local cycle = FunctionBrick.cycle(b.traits, Config)
	for _ = 1, math.floor(60 / STEP) do
		Session.advance(ctx, STEP)
		seen = math.max(seen, v.load.count)
		assertEqual(nil, output(b).log, "nothing reaches the output before the load is full")
		if v.load.count == 4 then
			break
		end
	end
	assertEqual(4, seen, "carrying a full load of " .. cycle .. "s items")
	assertTrue(west.amount == 0 and east.amount == 0, "both trees cut")

	run(ctx, 10)
	assertEqual(4, output(b).log)
	assertTrue(Load.empty(v.load))
	assertEqual(nil, v.job, "no node left: the operator lets go")
	assertEqual(nil, b.functionBricks[1].operator)
end)

test("with one log left in reach the operator returns with a part load, then lets go", function()
	local ctx, c = newSession()
	local b = build(ctx, c, design("saw"), 10, 10)
	node(ctx, "tree", 9, 10, 1)
	local v = villager(ctx)

	run(ctx, 20)

	assertEqual(1, output(b).log)
	assertTrue(Load.empty(v.load))
	assertEqual(nil, v.job)
	assertEqual(nil, b.functionBricks[1].operator)
end)

test("a 2-saw woodcutter gets two operators working two different trees", function()
	local ctx, c = newSession()
	local b = build(ctx, c, design("saw", "saw"), 10, 10)
	local west = node(ctx, "tree", 9, 10)
	local east = node(ctx, "tree", 12, 10)
	local v1, v2 = villager(ctx, 6, 10), villager(ctx, 15, 10)

	run(ctx, 6)

	local first, second = b.functionBricks[1], b.functionBricks[2]
	assertTrue(first.node ~= nil and second.node ~= nil, "both saws hold a node")
	assertTrue(first.node ~= second.node, "different nodes")
	assertTrue(v1.job and v2.job and v1.job ~= v2.job, "two operators")
	assertTrue(west.amount < Config.nodes.tree.amount and east.amount < Config.nodes.tree.amount, "both trees cut")
end)

-- Logs cut over `seconds` by two villagers, emptying the output every step
-- so it never fills.
local function yield(d, seconds)
	local ctx, c = newSession()
	local b = build(ctx, c, d, 10, 10)
	local trees = {}
	for y = 7, 14 do
		table.insert(trees, node(ctx, "tree", 8, y))
		table.insert(trees, node(ctx, "tree", 13, y))
	end
	villager(ctx, 9, 9)
	villager(ctx, 12, 9)
	for _ = 1, math.floor(seconds / STEP + 0.5) do
		Session.advance(ctx, STEP)
		for item in pairs(output(b)) do
			output(b)[item] = nil
		end
	end
	local cut = 0
	for _, t in ipairs(trees) do
		cut = cut + Config.nodes.tree.amount - t.amount
	end
	return cut
end

test("a 2-saw woodcutter yields more logs than a 1-saw woodcutter", function()
	local one = yield(design("saw"), 60)
	local two = yield(design("saw", "saw"), 60)
	assertTrue(one > 5, "the 1-saw cutter works: " .. one)
	assertTrue(two > one, two .. " vs " .. one)
end)

test("a saw and a pickaxe building yields both logs and stone", function()
	local ctx, c = newSession()
	local b = build(ctx, c, design("saw", "pickaxe"), 10, 10)
	node(ctx, "tree", 9, 10, 1)
	node(ctx, "rock", 12, 10, 1)
	villager(ctx, 8, 10)
	villager(ctx, 14, 10)

	run(ctx, 20)

	assertEqual(1, output(b).log)
	assertEqual(1, output(b).stone)
end)

test("a node beyond the building's reach is never harvested", function()
	local ctx, c = newSession()
	local b = build(ctx, c, design("saw"), 15, 15)
	local r = FunctionBrick.reach(b.traits, Config, "saw")
	local far = node(ctx, "tree", 15 - r - 1, 15)
	villager(ctx, 13, 13)

	run(ctx, FunctionBrick.cycle(b.traits, Config) * 3)

	assertEqual(Config.nodes.tree.amount, far.amount)
	local near = node(ctx, "tree", 15 - r, 15 + r, 1)
	run(ctx, 10)
	assertEqual(0, near.amount, "a node at reach, diagonally, is harvested")
end)

test("a full output ends the job and nothing more is harvested until it frees", function()
	local ctx, c = newSession()
	local b = build(ctx, c, design("saw"), 10, 10)
	local tree = node(ctx, "tree", 9, 10, 30)
	local v = villager(ctx)
	local size = b.ports[1].buffer.capacity

	run(ctx, 60)

	assertEqual(size, output(b).log)
	assertEqual(nil, v.job)
	local amount = tree.amount
	run(ctx, 10)
	assertEqual(amount, tree.amount, "nothing harvested while full")
	assertTrue(b.full, "the building shows it is full")

	Ports.collect(b.ports[1], c.inventory)
	run(ctx, 20)
	assertTrue(tree.amount < amount, "harvesting resumes")
end)

test("a node that dies under the operator frees their target and they take the next node", function()
	local ctx, c = newSession()
	local b = build(ctx, c, design("saw"), 10, 10)
	local first = node(ctx, "tree", 9, 10)
	local second = node(ctx, "tree", 9, 11)
	local v = villager(ctx, 8, 10)
	local fb = b.functionBricks[1]

	run(ctx, 1)
	assertEqual(first, fb.node)
	first.dead = true -- felled by hand
	run(ctx, 6)

	assertEqual(second, fb.node)
	assertTrue(second.amount < Config.nodes.tree.amount, "the next node is being cut")
	assertTrue(v.job ~= nil)
end)

test("productivity shortens the cycle and negative productivity lengthens it", function()
	local base = FunctionBrick.cycle({ productivity = 0 }, Config)
	assertEqual(Config.production.harvestCycle, base)
	assertTrue(FunctionBrick.cycle({ productivity = 10 }, Config) < base)
	assertTrue(FunctionBrick.cycle({ productivity = -10 }, Config) > base)
	local slowest = Config.production.harvestCycle / Config.production.minSpeed
	assertEqual(slowest, FunctionBrick.cycle({ productivity = -1000 }, Config))
end)

-- Seconds until the operator, standing beside the tree, has cut `n` logs.
local function secondsToCut(d, n)
	local ctx, c = newSession()
	build(ctx, c, d, 10, 10)
	local tree = node(ctx, "tree", 9, 10)
	villager(ctx, 8, 10)
	local t = 0
	while Config.nodes.tree.amount - tree.amount < n and t < 120 do
		Session.advance(ctx, STEP)
		t = t + STEP
	end
	return t
end

test("a building with more productivity harvests each item faster", function()
	local extra = {}
	for i = 0, 7 do
		table.insert(extra, brick("1x1", i, 2, 0))
		table.insert(extra, brick("1x1", i, 1, 0))
	end
	local plain = secondsToCut(design("saw"), 3)
	local productive = secondsToCut(design("saw", nil, extra), 3)
	assertTrue(productive < plain, productive .. " < " .. plain)
end)

test("harvest intent on an output port tile collects its items instead of hand-harvesting", function()
	local ctx, c = newSession()
	local b = build(ctx, c, design("saw"), 10, 10)
	local tree = node(ctx, "tree", 9, 10, 2)
	villager(ctx, 8, 10)
	run(ctx, 20)
	local amount = tree.amount
	assertEqual(2, output(b).log)

	local port = b.ports[1]
	c.x, c.y = (port.x + 0.5) * TILE, (port.y + 0.5) * TILE
	local roadside = node(ctx, "tree", port.x - 1, port.y)
	ctx.intents[1] = { x = 0, y = 0, harvest = true }
	Session.advance(ctx, STEP)
	ctx.intents[1] = nil

	assertEqual(2, Inventory.count(c.inventory, "log"))
	assertEqual(nil, output(b).log)
	assertEqual(Config.nodes.tree.amount, roadside.amount, "no hand harvest while collecting")
	assertEqual(amount, tree.amount)
end)

test("a saw reaches 10 tiles for trees; other abilities keep the base reach", function()
	assertEqual(10, FunctionBrick.reach({ reach = 0 }, Config, "saw"))
	assertEqual(Config.production.reachBase, FunctionBrick.reach({ reach = 0 }, Config, "pickaxe"))
	assertEqual(Config.production.reachBase, FunctionBrick.reach({ reach = 0 }, Config))
end)
