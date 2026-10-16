-- Node reservations (src/game/systems/node_system.lua): a function brick
-- holds one node at a time and no other brick may take it; the hold ends
-- when the node is depleted or the building is removed. A saw reserves only
-- once a villager operates it.
local Session = require("src.game.session")
local World = require("src.game.world")
local Config = require("src.game.config")
local Placement = require("src.game.buildings.placement")
local Inventory = require("src.game.components.inventory")
local FunctionBrick = require("src.game.components.function_brick")
local NodeSystem = require("src.game.systems.node_system")

local STEP = 1 / 60

local function brick(x, y, fields)
	local b = { x = x, y = y, z = 0, width = 1, depth = 1, height = 1, shape = "1x1", rotation = 0, material = "plank", paint = 1 }
	for k, v in pairs(fields or {}) do
		b[k] = v
	end
	return b
end

local function saw(x, y)
	return brick(x, y, { width = 3, height = 3, shape = "saw", ability = "saw" })
end

-- A 1x1 tile cutter: one saw and an output port facing the tile south of it.
local CUTTER = {
	id = "d1",
	name = "Cutter",
	versions = {
		{ width = 1, depth = 1, bricks = { saw(0, 0), brick(1, 3, { width = 2, shape = "output", port = "output" }) } },
	},
}

local function newSession()
	local ctx = Session.new(World.new(30, 30), Config, 1)
	local c = ctx.pools.characters[1]
	c.inventory = Inventory.new({ plank = 10000, stone = 10000 })
	return ctx, c
end

local function build(ctx, c, x, y)
	return assert(Placement.build(ctx, { design = CUTTER, version = 1, facing = "N", tileX = x, tileY = y }))
end

local function tree(ctx, x, y, amount)
	return World.addNode(ctx.world, { id = x * 100 + y, kind = "tree", tileX = x, tileY = y, variant = 1, stage = 1, amount = amount or Config.nodes.tree.amount })
end

local function villager(ctx, tileX, tileY)
	local tile = Config.tileSize
	local v = Session.newVillager(#ctx.pools.villagers + 1, (tileX + 0.5) * tile, (tileY + 0.5) * tile, Config)
	table.insert(ctx.pools.villagers, v)
	return v
end

local function run(ctx, seconds)
	for _ = 1, math.floor(seconds / STEP + 0.5) do
		Session.advance(ctx, STEP)
	end
end

test("a reserved node is skipped by another building's saw", function()
	local ctx, c = newSession()
	local a = build(ctx, c, 10, 10)
	local t = tree(ctx, 11, 10)
	villager(ctx, 10, 12)
	run(ctx, STEP)
	local b = build(ctx, c, 12, 10)
	villager(ctx, 12, 12)
	run(ctx, STEP)

	assertEqual(t, a.functionBricks[1].node)
	assertEqual(a.functionBricks[1], t.reservedBy)
	assertEqual(nil, b.functionBricks[1].node, "the second saw finds nothing free")
	assertEqual("idle", b.functionBricks[1].state)
end)

test("a depleted node releases its saw, which reserves the next node", function()
	local ctx, c = newSession()
	local a = build(ctx, c, 10, 10)
	local first = tree(ctx, 11, 10, 1)
	villager(ctx, 10, 12)
	local cycle = FunctionBrick.cycle(a.traits, Config)
	run(ctx, cycle + 2)

	assertTrue(first.dead)
	assertEqual(nil, first.reservedBy)
	assertEqual(nil, World.nodeAt(ctx.world, 11, 10), "swept")
	local second = tree(ctx, 9, 10)
	run(ctx, 4)
	assertEqual(second, a.functionBricks[1].node)
end)

test("a node felled by hand releases its saw before any saw picks a target", function()
	local ctx, c = newSession()
	local a = build(ctx, c, 10, 10)
	local t = tree(ctx, 11, 10)
	villager(ctx, 10, 12)
	run(ctx, STEP)
	assertEqual(t, a.functionBricks[1].node)

	t.amount, t.dead = 0, true -- as Harvestable.work leaves it
	NodeSystem.releaseDead(ctx)
	assertEqual(nil, a.functionBricks[1].node)
	assertEqual(nil, t.reservedBy)

	local other = tree(ctx, 9, 10)
	run(ctx, 4)
	assertEqual(other, a.functionBricks[1].node, "the saw never re-takes a depleted node")
end)

test("removing a building releases its reservations and frees its tiles", function()
	local ctx, c = newSession()
	local a = build(ctx, c, 10, 10)
	local t = tree(ctx, 11, 10)
	villager(ctx, 10, 12)
	run(ctx, STEP)
	assertEqual(a.functionBricks[1], t.reservedBy)

	a.dead = true
	run(ctx, STEP)

	assertEqual(nil, t.reservedBy)
	assertEqual(0, #ctx.pools.buildings)
	assertEqual(nil, World.buildingAt(ctx.world, 10, 10))
	assertEqual(nil, World.portAt(ctx.world, 10, 11))
	local b = build(ctx, c, 12, 10)
	run(ctx, STEP)
	assertEqual(t, b.functionBricks[1].node, "another saw may take the node")
end)
