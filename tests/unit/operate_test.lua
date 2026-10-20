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
local AnimalSystem = require("src.game.systems.animal_system")

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

test("an operator may enter its building while it holds the job, and loses that when the job ends", function()
	local ctx, mill, v = setup()
	local job = Operate.new(mill, mill.functionBricks[1])
	assertEqual(nil, v.mover.enter)
	assertTrue(Operate.start(job, v, ctx))
	assertTrue(v.mover.enter == mill, "enter is the job's building")
	Operate.finish(job)
	assertEqual(nil, v.mover.enter)
end)

test("an operator that cannot start (no route) does not keep the right to enter", function()
	local ctx, mill, v = setup()
	-- Wall the villager in with water.
	for y = 2, 4 do
		for x = 2, 4 do
			if x ~= 3 or y ~= 3 then
				World.setTerrain(ctx.world, x, y, "water")
			end
		end
	end
	local job = Operate.new(mill, mill.functionBricks[1])
	assertFalse(Operate.start(job, v, ctx))
	assertEqual(nil, v.mover.enter)
end)

test("a saw bench operator reaches its brick tile inside the footprint", function()
	local ctx, mill, v = setup()
	local fb = mill.functionBricks[1]
	local job = Operate.new(mill, fb)
	Operate.start(job, v, ctx)
	run(ctx, job, v, 60 * 60, function()
		return job.stage == "working"
	end)
	assertEqual("working", job.stage)
	assertEqual(fb.tileX, math.floor(v.x / TILE))
	assertEqual(fb.tileY, math.floor(v.y / TILE))
	assertTrue(World.buildingAt(ctx.world, fb.tileX, fb.tileY) == mill, "the brick tile is in the footprint")
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

test("a harvester's stand tile never lies on another building's footprint", function()
	local ctx, b, tree, v = cutterWithTree()
	local fb = b.functionBricks[1]
	-- Every tile beside the tree belongs to someone else's building.
	World.addBuilding(ctx.world, { tileX = 7, tileY = 5, width = 3, depth = 3, ports = {} })
	local job = Operate.new(b, fb)
	assertFalse(Operate.start(job, v, ctx), "no free tile beside the tree: the job ends")
	assertEqual(nil, v.mover.enter)
	assertEqual(nil, fb.node)
end)

test("a finished operator cycle adds one to the brick's ability, and nothing else", function()
	local ctx, b, tree, v = cutterWithTree()
	local out = b.ports[1].buffer
	fill(out, "log", out.capacity - 1)
	local job = Operate.new(b, b.functionBricks[1])
	Operate.start(job, v, ctx)
	run(ctx, job, v, 60 * 120)
	assertTrue(job.dead)
	local key = b.functionBricks[1].ability
	assertEqual(1, v.xp[key])
	local others = 0
	for k in pairs(v.xp) do
		others = others + (k ~= key and 1 or 0)
	end
	assertEqual(0, others)
end)

local ANGLER = { id = "d9", name = "Angler", versions = { { width = 2, depth = 1, bricks = {
	brick("fishing", 0, 0, { width = 3, ability = "fishing" }),
	brick("output", 3, 3, { port = "output" }),
} } } }

local function angler(waterX, waterY)
	local ctx = Session.new(World.new(40, 40), Config, 1)
	ctx.dt = STEP
	if waterX then
		World.setTerrain(ctx.world, waterX, waterY, "water")
	end
	local b = Placement.build(ctx, { design = ANGLER, version = 1, facing = "N", tileX = 8, tileY = 8 })
	return ctx, b
end

test("a fishing brick has work only while water is in reach", function()
	local ctx, b = angler()
	assertEqual(false, FunctionBrick.hasWork(b.functionBricks[1], b, ctx), "no water")
	local ctx2, b2 = angler(8 + 3 + Config.production.abilityReach.fishing + 1, 8)
	assertEqual(false, FunctionBrick.hasWork(b2.functionBricks[1], b2, ctx2), "water out of reach")
	local ctx3, b3 = angler(13, 8)
	assertEqual(true, FunctionBrick.hasWork(b3.functionBricks[1], b3, ctx3), "water in reach")
end)

test("a fisher stands on land beside the water, never on it, and delivers a fish", function()
	local ctx, b = angler(13, 9)
	local v = Session.newVillager(1, 3.5 * TILE, 3.5 * TILE, Config)
	local job = Operate.new(b, b.functionBricks[1])
	assertTrue(Operate.start(job, v, ctx))
	local out = b.ports[1].buffer
	for _ = 1, 60 * 120 do
		Walker.step(v, ctx)
		Operate.step(job, ctx)
		local tx, ty = math.floor(v.x / TILE), math.floor(v.y / TILE)
		assertEqual("grass", World.terrainAt(ctx.world, tx, ty), "never on water")
		if (out.counts.fish or 0) >= 1 then
			break
		end
	end
	assertEqual(1, out.counts.fish)
	assertTrue(Load.empty(v.load), "fish delivered")
end)

local HUNTER = { id = "d10", name = "Hunter", versions = { { width = 2, depth = 1, bricks = {
	brick("hunter", 0, 0, { width = 3, ability = "hunter" }),
	brick("output", 3, 3, { port = "output" }),
} } } }

-- A hunter building at tile (8, 8) in an open world, with deer at `spots`
-- (tiles) of one herd.
local function huntRange(spots)
	local ctx = Session.new(World.new(30, 30), Config, 1)
	ctx.dt = STEP
	local b = Placement.build(ctx, { design = HUNTER, version = 1, facing = "N", tileX = 8, tileY = 8 })
	local herd = AnimalSystem.addHerd(ctx, 12, 12, 4)
	local deer = {}
	for i, s in ipairs(spots) do
		deer[i] = AnimalSystem.spawn(ctx, herd, s[1], s[2])
	end
	return ctx, b, deer
end

test("a hunter brick has work only while a free deer is in reach and an output has room", function()
	local ctx, b = huntRange({})
	assertEqual(false, FunctionBrick.hasWork(b.functionBricks[1], b, ctx), "no deer")
	local ctx2, b2 = huntRange({ { 8 + 3 + Config.production.abilityReach.hunter + 1, 8 } })
	assertEqual(false, FunctionBrick.hasWork(b2.functionBricks[1], b2, ctx2), "deer out of reach")
	local ctx3, b3 = huntRange({ { 13, 9 } })
	assertEqual(true, FunctionBrick.hasWork(b3.functionBricks[1], b3, ctx3), "deer in reach")
	AnimalSystem.reserve(ctx3.pools.animals[1], {})
	assertEqual(false, FunctionBrick.hasWork(b3.functionBricks[1], b3, ctx3), "the only deer is reserved")
end)

test("two hunters never reserve the same deer", function()
	local ctx, b, deer = huntRange({ { 13, 9 }, { 14, 9 } })
	local a = Session.newVillager(1, 3.5 * TILE, 3.5 * TILE, Config)
	local c = Session.newVillager(2, 3.5 * TILE, 4.5 * TILE, Config)
	local fb = b.functionBricks[1]
	local j1 = Operate.new(b, fb)
	assertTrue(Operate.start(j1, a, ctx))
	local d1 = j1.deer
	local b2 = Placement.build(ctx, { design = HUNTER, version = 1, facing = "N", tileX = 8, tileY = 14 })
	local j2 = Operate.new(b2, b2.functionBricks[1])
	assertTrue(Operate.start(j2, c, ctx))
	assertTrue(d1 ~= nil and j2.deer ~= nil and d1 ~= j2.deer, "different deer")
	local b3 = Placement.build(ctx, { design = HUNTER, version = 1, facing = "N", tileX = 15, tileY = 14 })
	local j3 = Operate.new(b3, b3.functionBricks[1])
	assertEqual(false, Operate.start(j3, Session.newVillager(3, 3.5 * TILE, 5.5 * TILE, Config), ctx), "no free deer left")
end)

test("a hunter kills a deer, which despawns, and delivers its meat", function()
	local ctx, b, deer = huntRange({ { 13, 9 } })
	local v = Session.newVillager(1, 3.5 * TILE, 3.5 * TILE, Config)
	local job = Operate.new(b, b.functionBricks[1])
	assertTrue(Operate.start(job, v, ctx))
	local out = b.ports[1].buffer
	for _ = 1, 60 * 120 do
		Walker.step(v, ctx)
		Operate.step(job, ctx)
		if (out.counts.meat or 0) >= 1 then
			break
		end
	end
	assertEqual(Config.production.meatPerDeer, out.counts.meat)
	assertTrue(deer[1].dead, "the deer is dead")
	assertTrue(Load.empty(v.load), "meat delivered")
	AnimalSystem.despawn(ctx)
	assertEqual(0, #ctx.pools.animals)
end)

test("a reserved deer stops wandering; one that leaves reach is released and re-targeted", function()
	local ctx, b, deer = huntRange({ { 13, 9 }, { 12, 12 } })
	local v = Session.newVillager(1, 3.5 * TILE, 3.5 * TILE, Config)
	local job = Operate.new(b, b.functionBricks[1])
	assertTrue(Operate.start(job, v, ctx))
	local first = job.deer
	-- Walk the reserved deer out of reach by hand.
	first.x, first.y = 29.5 * TILE, 29.5 * TILE
	local was = first.x
	for _ = 1, 60 * 20 do
		Walker.step(v, ctx)
		AnimalSystem.update(ctx)
		Operate.step(job, ctx)
		if job.deer ~= first then
			break
		end
	end
	assertTrue(job.deer ~= first and job.deer ~= nil, "re-targeted")
	assertTrue(first.hunter == nil, "old deer released")
	assertEqual(was, first.x, "the far deer never wandered")
end)

-- Auras (docs/CONTEXT.md "Aura"): the operating villager's harvestRate scales
-- every work cycle's progress. Walks to `stage`, then returns the brick's
-- progress gained by one more step with the villager's aura at `rate`.
local function progressGain(ctx, b, v, stage, rate)
	local job = Operate.new(b, b.functionBricks[1])
	assertTrue(Operate.start(job, v, ctx))
	v.aura = { walkSpeed = 0, harvestRate = rate }
	run(ctx, job, v, 60 * 60, function()
		return job.stage == stage and Walker.idle(v.walker)
	end)
	assertEqual(stage, job.stage)
	local fb = b.functionBricks[1]
	local before = fb.progress
	Walker.step(v, ctx)
	Operate.step(job, ctx)
	return fb.progress - before
end

local PLANTER = { id = "d11", name = "Forester", versions = { { width = 2, depth = 1, bricks = {
	brick("planter", 0, 0, { width = 4, depth = 2, ability = "planter" }),
} } } }

local AURA_CASES = {
	{ "convert", "working", function()
		local ctx, b, v = setup()
		return ctx, b, v
	end },
	{ "harvest", "harvesting", function()
		local ctx, b, _, v = cutterWithTree()
		return ctx, b, v
	end },
	{ "plant", "seeding", function()
		local ctx = Session.new(World.new(20, 20), Config, 1)
		ctx.dt = STEP
		local b = Placement.build(ctx, { design = PLANTER, version = 1, facing = "N", tileX = 8, tileY = 8 })
		return ctx, b, Session.newVillager(1, 3.5 * TILE, 3.5 * TILE, Config)
	end },
	{ "fish", "fishing", function()
		local ctx, b = angler(13, 9)
		return ctx, b, Session.newVillager(1, 3.5 * TILE, 3.5 * TILE, Config)
	end },
	{ "hunt", "killing", function()
		local ctx, b = huntRange({ { 13, 9 } })
		return ctx, b, Session.newVillager(1, 3.5 * TILE, 3.5 * TILE, Config)
	end },
}

for _, case in ipairs(AURA_CASES) do
	local name, stage, make = case[1], case[2], case[3]
	test("a " .. name .. " operator's cycle progresses faster by the villager's work rate aura", function()
		local ctx, b, v = make()
		local base = progressGain(ctx, b, v, stage, 0)
		assertNear(STEP, base, 1e-9)
		local ctx2, b2, v2 = make()
		local boosted = progressGain(ctx2, b2, v2, stage, 1)
		assertNear(2 * STEP, boosted, 1e-9)
	end)
end
