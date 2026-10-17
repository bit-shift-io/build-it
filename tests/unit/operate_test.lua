-- The operator job framework (src/game/jobs/operate.lua, docs/CONTEXT.md
-- "Operator job"): one villager holds a function brick's job, and it ends,
-- freeing both, when the building is gone or a walk has no route. Driven
-- here through a saw bench.
local Session = require("src.game.session")
local World = require("src.game.world")
local Config = require("src.game.config")
local Placement = require("src.game.buildings.placement")
local Storage = require("src.game.components.storage")
local Walker = require("src.game.components.walker")
local FunctionBrick = require("src.game.components.function_brick")
local Operate = require("src.game.jobs.operate")
local Load = require("src.game.components.load")

local TILE = Config.tileSize
local STEP = 1 / 60

local function brick(shape, x, y, extra)
	local b = { x = x, y = y, z = 0, width = 2, depth = 1, height = 1, shape = shape, rotation = 0, material = "plank", paint = 1 }
	for k, v in pairs(extra or {}) do
		b[k] = v
	end
	return b
end

local MILL = { id = "d1", name = "Mill", versions = { { width = 2, depth = 1, bricks = {
	brick("sawbench", 0, 0, { width = 4, depth = 2, ability = "sawbench" }),
	brick("input", 0, 3, { port = "input" }),
	brick("output", 4, 3, { port = "output" }),
} } } }

local function setup()
	local ctx = Session.new(World.new(20, 20), Config, 1)
	ctx.dt = STEP
	local mill = Placement.build(ctx, { design = MILL, version = 1, facing = "N", tileX = 8, tileY = 8 })
	local v = Session.newVillager(1, 3.5 * TILE, 3.5 * TILE, Config)
	for _ = 1, 2 do
		Storage.add(mill.ports[1].buffer, "log")
	end
	return ctx, mill, v
end

local function run(ctx, job, v, steps, done)
	for _ = 1, steps do
		if job.dead or (done and done()) then
			return
		end
		Walker.step(v, ctx)
		Operate.step(job, ctx)
	end
end

test("an operator job ends when its building is gone; the villager keeps what it carries", function()
	local ctx, mill, v = setup()
	local fb = mill.functionBricks[1]
	local job = Operate.new(mill, fb)
	assertTrue(Operate.start(job, v, ctx))
	assertTrue(v.job == job and fb.operator == job)
	run(ctx, job, v, 60 * 30, function()
		return job.stage == "toBrick"
	end)
	assertEqual(2, v.load.count, "carrying the logs")

	mill.dead = true
	Operate.step(job, ctx)
	assertTrue(job.dead)
	assertEqual(nil, v.job)
	assertEqual(nil, fb.operator)
	assertEqual("log", v.load.item)
	assertEqual(2, v.load.count)
end)

test("an operator heading to the output reserves one room there and frees it when the job ends", function()
	local ctx, mill, v = setup()
	local out = mill.ports[2].buffer
	local job = Operate.new(mill, mill.functionBricks[1])
	Operate.start(job, v, ctx)
	run(ctx, job, v, 60 * 60, function()
		return job.stage == "toOutput"
	end)
	assertEqual(out.capacity - 1, Storage.room(out))
	Operate.finish(job)
	assertEqual(out.capacity, Storage.room(out))
	assertEqual("plank", v.load.item)
end)

test("an operator job with no route ends at once and frees the brick", function()
	local ctx, mill, v = setup()
	local port = mill.ports[1]
	-- The villager stands walled in by water.
	v.x, v.y = 1.5 * TILE, 1.5 * TILE
	for y = 0, 3 do
		for x = 0, 3 do
			if not (x == 1 and y == 1) then
				World.setTerrain(ctx.world, x, y, "water")
			end
		end
	end

	local fb = mill.functionBricks[1]
	local job = Operate.new(mill, fb)
	assertFalse(Operate.start(job, v, ctx))
	assertTrue(job.dead)
	assertEqual(nil, v.job)
	assertEqual(nil, fb.operator)
	assertEqual(2, port.buffer.counts.log, "nothing taken")
end)

local CUTTER = { id = "d2", name = "Cutter", versions = { { width = 2, depth = 1, bricks = {
	brick("saw", 0, 0, { width = 3, depth = 1, ability = "saw" }),
	brick("output", 4, 3, { port = "output" }),
} } } }

test("a harvester job whose node has no free neighbour ends at once and frees the node", function()
	local ctx = Session.new(World.new(20, 20), Config, 1)
	ctx.dt = STEP
	local b = Placement.build(ctx, { design = CUTTER, version = 1, facing = "N", tileX = 8, tileY = 8 })
	-- A tree on a tile ringed by water.
	for y = 5, 7 do
		for x = 5, 7 do
			World.setTerrain(ctx.world, x, y, "water")
		end
	end
	World.setTerrain(ctx.world, 6, 6, "grass")
	local tree = World.addNode(ctx.world, { id = 1, kind = "tree", tileX = 6, tileY = 6, variant = 1, stage = 1, amount = 5 })
	local v = Session.newVillager(1, 12.5 * TILE, 12.5 * TILE, Config)
	local fb = b.functionBricks[1]
	local job = Operate.new(b, fb)

	assertTrue(FunctionBrick.nearestFree(b, "tree", ctx) == tree, "fixture: the tree is in reach")
	assertFalse(Operate.start(job, v, ctx))
	assertTrue(job.dead)
	assertEqual(nil, fb.node)
	assertEqual(nil, tree.reservedBy)
	assertEqual(nil, v.job)
end)

local function fill(store, item, n)
	for _ = 1, n do
		Storage.add(store, item)
	end
end

test("a saw bench operator with no output room takes no logs; the job ends at once", function()
	local ctx, mill, v = setup()
	local out = mill.ports[2].buffer
	fill(out, "plank", out.capacity)
	local job = Operate.new(mill, mill.functionBricks[1])

	assertFalse(Operate.start(job, v, ctx))
	assertEqual(2, mill.ports[1].buffer.counts.log, "nothing taken")
	assertTrue(Load.empty(v.load))
end)

test("a saw bench operator holds its output room from before it takes the logs until the job ends", function()
	local ctx, mill, v = setup()
	local out = mill.ports[2].buffer
	fill(out, "plank", out.capacity - 1)
	local job = Operate.new(mill, mill.functionBricks[1])
	Operate.start(job, v, ctx)
	run(ctx, job, v, 60 * 30, function()
		return job.stage == "toBrick"
	end)
	assertEqual(2, v.load.count, "carrying the logs")
	assertEqual(0, Storage.room(out), "its one free slot is held for the plank")

	Operate.finish(job)
	assertEqual(1, Storage.room(out))
end)

local function cutterWithTree()
	local ctx = Session.new(World.new(20, 20), Config, 1)
	ctx.dt = STEP
	local b = Placement.build(ctx, { design = CUTTER, version = 1, facing = "N", tileX = 8, tileY = 8 })
	local tree = World.addNode(ctx.world, { id = 1, kind = "tree", tileX = 8, tileY = 6, variant = 1, stage = 1, amount = 5 })
	local v = Session.newVillager(1, 12.5 * TILE, 12.5 * TILE, Config)
	return ctx, b, tree, v
end

test("a woodcutter operator with one free output slot harvests one log, delivers it and holds nothing", function()
	local ctx, b, tree, v = cutterWithTree()
	local out = b.ports[1].buffer
	fill(out, "log", out.capacity - 1)
	local job = Operate.new(b, b.functionBricks[1])
	assertTrue(Operate.start(job, v, ctx))

	local most = 0
	run(ctx, job, v, 60 * 60, function()
		most = math.max(most, v.load.count)
		return false
	end)
	assertTrue(job.dead, "the job ended once the output was full")
	assertEqual(1, most, "never carried more than the room it held")
	assertEqual(out.capacity, out.counts.log)
	assertEqual(4, tree.amount)
	assertTrue(Load.empty(v.load))
end)

test("a woodcutter operator ended mid-harvest gives back the room it held", function()
	local ctx, b, _, v = cutterWithTree()
	local out = b.ports[1].buffer
	local job = Operate.new(b, b.functionBricks[1])
	Operate.start(job, v, ctx)
	run(ctx, job, v, 60 * 60, function()
		return v.load.count == 2
	end)
	assertEqual(out.capacity - 2, Storage.room(out), "room held for the two logs carried")

	Operate.finish(job)
	assertEqual(out.capacity, Storage.room(out))
end)
