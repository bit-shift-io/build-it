-- Planter function bricks: an operator villager plants one sapling per trip
-- on a free grass tile in reach, never on footprints, port tiles, water or
-- other nodes. An unstaffed planter plants nothing.
local Session = require("src.game.session")
local World = require("src.game.world")
local Config = require("src.game.config")
local Placement = require("src.game.buildings.placement")
local Inventory = require("src.game.components.inventory")
local FunctionBrick = require("src.game.components.function_brick")
local NodeSystem = require("src.game.systems.node_system")

local STEP = 1 / 60

local Designs = require("tests.support.designs")

-- A 2x1 forester: a planter, and with `withPort` an output port on the
-- south edge under tile 0.
local function design(withPort)
	if withPort then
		return Designs.floor(2, 1, Designs.ability("planter", 0.5, 0.25), Designs.port("output", 0.25, 1))
	end
	return Designs.floor(2, 1, Designs.ability("planter", 0.5, 0.25))
end

local function setup(withPort, villagers)
	local ctx = Session.new(World.new(30, 30), Config, 1)
	for i = 1, villagers == nil and 1 or villagers do
		table.insert(ctx.pools.villagers, Session.newVillager(i, (8 + i) * Config.tileSize, 8.5 * Config.tileSize, Config))
	end
	local c = ctx.pools.characters[1]
	c.inventory = Inventory.new({ plank = 10000, stone = 10000 })
	local b = assert(Placement.build(ctx, Designs.request(design(withPort), "N", 10, 10)))
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

test("an unstaffed planter plants nothing", function()
	local ctx, b = setup(false, 0)
	run(ctx, cycle(b) * 10)
	assertEqual(0, #ctx.pools.nodes)
end)

test("a staffed planter's operator plants saplings on tiles it walked to", function()
	local ctx, b = setup()
	local v = ctx.pools.villagers[1]
	local fb = b.functionBricks[1]
	local seen = 0
	for _ = 1, 60 * 60 do
		Session.advance(ctx, STEP)
		if #ctx.pools.nodes > seen then
			seen = #ctx.pools.nodes
			local n = ctx.pools.nodes[seen]
			local tile = Config.tileSize
			assertEqual(n.tileX, math.floor(v.x / tile))
			assertEqual(n.tileY, math.floor(v.y / tile))
			assertEqual("tree", n.kind)
			assertTrue(n.growing ~= nil, "growing")
			assertTrue(n.variant >= 1 and n.variant <= Config.props.variants)
		end
	end
	assertTrue(seen >= 3, "planted several saplings")
	assertEqual(v.job, fb.operator)
end)

test("two planters never reserve the same tile", function()
	local ctx, b = setup(false, 2)
	local ok = true
	for _ = 1, 60 * 60 do
		Session.advance(ctx, STEP)
		local taken = {}
		for _, v in ipairs(ctx.pools.villagers) do
			local t = v.job and v.job.target
			if t then
				local key = t[1] .. "," .. t[2]
				ok = ok and not taken[key]
				taken[key] = true
			end
		end
	end
	assertTrue(ok, "no tile held twice")
	assertTrue(#ctx.pools.nodes > 3)
end)

test("the operator lets go of the job when no free tile is in reach", function()
	local ctx, b = setup()
	local reach = FunctionBrick.reach(b.traits, Config)
	run(ctx, cycle(b) * 8)
	local fb = b.functionBricks[1]
	assertTrue(fb.operator ~= nil, "fixture: staffed while tiles are free")
	-- Fill the tiles while the operator holds none, so none is left free.
	for _ = 1, 60 * 60 do
		if fb.operator.stage == "seeding" then
			break
		end
		Session.advance(ctx, STEP)
	end
	for _, tile in ipairs(FunctionBrick.freeTiles(b, ctx)) do
		NodeSystem.plant(ctx, "tree", tile[1], tile[2]) -- something else fills every tile
	end
	run(ctx, cycle(b) * 3)
	assertEqual(nil, b.functionBricks[1].operator)
	assertEqual(nil, ctx.pools.villagers[1].job)
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

test("a tile taken before the operator arrives is not planted", function()
	local ctx, b = setup()
	local fb = b.functionBricks[1]
	local job
	for _ = 1, 60 * 20 do
		Session.advance(ctx, STEP)
		if fb.operator and fb.operator.target then
			job = fb.operator
			break
		end
	end
	assertTrue(job ~= nil, "operator picked a tile")
	local x, y = job.target[1], job.target[2]
	local before = #ctx.pools.nodes
	NodeSystem.plant(ctx, "tree", x, y) -- something else takes the tile
	run(ctx, 1)
	local count = 0
	for _, n in ipairs(ctx.pools.nodes) do
		if n.tileX == x and n.tileY == y then
			count = count + 1
		end
	end
	assertEqual(1, count)
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
