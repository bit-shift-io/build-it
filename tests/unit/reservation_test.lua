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
local Storage = require("src.game.components.storage")
local Load = require("src.game.components.load")

local STEP = 1 / 60

local Designs = require("tests.support.designs")

-- A 1x1 tile cutter: one saw and an output port facing the tile south of it.
local CUTTER = Designs.floor(1, 1, Designs.ability("saw", 0.375, 0.125), Designs.port("output", 0.5, 1))

local function newSession()
	local ctx = Session.new(World.new(30, 30), Config, 1)
	local c = ctx.pools.characters[1]
	c.inventory = Inventory.new({ plank = 10000, stone = 10000 })
	return ctx, c
end

local function build(ctx, c, x, y)
	return assert(Placement.build(ctx, Designs.request(CUTTER, "N", x, y)))
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

-- A 1x1 tile storage facility with ports on its south edge.
local DEPOT = Designs.floor(1, 1,
	Designs.ability("depot", 0.25, 0.25),
	Designs.storage(8, 0.75, 0.25),
	Designs.port("input", 0.25, 1),
	Designs.port("output", 0.75, 1))

test("with every output and storage facility full, no free villager is left holding a load", function()
	local ctx, c = newSession()
	local a = build(ctx, c, 10, 10)
	tree(ctx, 11, 10)
	local out = a.ports[1].buffer
	for _ = 1, out.capacity - 1 do
		Storage.add(out, "log")
	end
	local depot = assert(Placement.build(ctx, Designs.request(DEPOT, "N", 20, 10)))
	for _, store in ipairs({ depot.storage, depot.ports[1].buffer, depot.ports[2].buffer }) do
		while Storage.room(store) > 0 do
			Storage.add(store, "stone")
		end
	end
	villager(ctx, 10, 12)
	villager(ctx, 14, 12)

	for _ = 1, 60 * 60 do
		Session.advance(ctx, STEP)
		for _, v in ipairs(ctx.pools.villagers) do
			assertTrue(v.job or Load.empty(v.load), "villager " .. v.id .. " free with " .. v.load.count .. " " .. tostring(v.load.item))
		end
	end
	assertEqual(out.capacity, out.counts.log, "the one free slot was filled")
end)
