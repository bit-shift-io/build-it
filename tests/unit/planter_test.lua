-- Planter function bricks: one sapling per cycle on a free grass tile in
-- reach, never on footprints, port tiles, water or other nodes.
local Session = require("src.game.session")
local World = require("src.game.world")
local Config = require("src.game.config")
local Placement = require("src.game.buildings.placement")
local Inventory = require("src.game.components.inventory")
local FunctionBrick = require("src.game.components.function_brick")

local STEP = 1 / 60

local function brick(shape, x, y, f)
	return { x = x, y = y, z = 0, width = f.width, depth = f.depth, height = 1, shape = shape, rotation = 0, material = "plank", paint = 1, ability = f.ability, port = f.port }
end

local function design(withPort)
	local bricks = { brick("planter", 0, 0, { width = 4, depth = 2, ability = "planter" }) }
	if withPort then
		table.insert(bricks, brick("output", 0, 3, { width = 2, depth = 1, port = "output" }))
	end
	return { id = "d1", name = "Forester", versions = { { width = 2, depth = 1, bricks = bricks } } }
end

local function setup(withPort)
	local ctx = Session.new(World.new(30, 30), Config, 1)
	local c = ctx.pools.characters[1]
	c.inventory = Inventory.new({ plank = 10000, stone = 10000 })
	local b = assert(Placement.place(ctx, c, { design = design(withPort), version = 1, facing = "N", tileX = 10, tileY = 10 }))
	return ctx, b
end

local function run(ctx, seconds)
	for _ = 1, math.floor(seconds / STEP + 0.5) do
		Session.advance(ctx, STEP)
	end
end

local function cycle(b)
	return FunctionBrick.cycle(b.traits, Config, Config.production.plantCycle)
end

test("a planter makes a planter record", function()
	local _, b = setup()
	assertEqual("planter", b.functionBricks[1].ability)
	assertEqual("tree", b.functionBricks[1].plants)
end)

test("a planter plants one sapling per cycle", function()
	local ctx, b = setup()
	run(ctx, cycle(b) * 3.5)
	assertEqual(3, #ctx.pools.nodes)
	for _, n in ipairs(ctx.pools.nodes) do
		assertEqual("tree", n.kind)
		assertTrue(n.growing ~= nil, "growing")
		assertEqual(Config.nodes.tree.amount, n.amount)
		assertTrue(n.variant >= 1 and n.variant <= Config.props.variants)
	end
end)

test("saplings land within reach, on free grass only, never on ports or footprints", function()
	local ctx, b = setup(true)
	World.setTerrain(ctx.world, 9, 9, "water")
	local reach = FunctionBrick.reach(b.traits, Config)
	run(ctx, cycle(b) * 200)
	local ids = {}
	for _, n in ipairs(ctx.pools.nodes) do
		assertFalse(ids[n.id], "unique ids")
		ids[n.id] = true
		assertTrue(n.tileX >= 10 - reach and n.tileX <= 10 + b.width - 1 + reach, "x in reach")
		assertTrue(n.tileY >= 10 - reach and n.tileY <= 10 + b.depth - 1 + reach, "y in reach")
		assertEqual(nil, World.buildingAt(ctx.world, n.tileX, n.tileY))
		assertEqual(nil, World.portAt(ctx.world, n.tileX, n.tileY))
		assertEqual("grass", World.terrainAt(ctx.world, n.tileX, n.tileY))
	end
	assertEqual(nil, World.nodeAt(ctx.world, 9, 9))
	assertTrue(#ctx.pools.nodes > 5)
end)

test("a planter stops when every tile in reach is taken", function()
	local ctx, b = setup()
	local reach = FunctionBrick.reach(b.traits, Config)
	run(ctx, cycle(b) * 1000)
	local tiles = (b.width + 2 * reach) * (b.depth + 2 * reach) - b.width * b.depth
	assertEqual(tiles, #ctx.pools.nodes)
	assertEqual("idle", b.functionBricks[1].state)
end)

test("planting is deterministic for a seed", function()
	local function layout()
		local ctx, b = setup()
		run(ctx, cycle(b) * 10)
		local out = {}
		for _, n in ipairs(ctx.pools.nodes) do
			table.insert(out, n.tileX .. "," .. n.tileY .. "," .. n.variant)
		end
		return table.concat(out, ";")
	end
	assertEqual(layout(), layout())
end)
