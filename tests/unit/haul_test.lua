-- Haul jobs (docs/CONTEXT.md "Haul job"): one villager walks to the source,
-- picks up one load, walks to the destination and drops it. A job reserves
-- its source items and destination room while it is open and releases them
-- when it ends or fails.
local Session = require("src.game.session")
local World = require("src.game.world")
local Config = require("src.game.config")
local Placement = require("src.game.buildings.placement")
local Storage = require("src.game.components.storage")
local Walker = require("src.game.components.walker")
local Load = require("src.game.components.load")
local Haul = require("src.game.jobs.haul")

local TILE = Config.tileSize
local STEP = 1 / 60

local function brick(shape, x, y, extra)
	local b = { x = x, y = y, z = 0, width = 2, depth = 1, height = 1, shape = shape, rotation = 0, material = "plank", paint = 1 }
	for k, v in pairs(extra or {}) do
		b[k] = v
	end
	return b
end

-- 1x1 tile buildings with one port on the south edge.
local CUTTER = { id = "d1", name = "Cutter", versions = { { width = 1, depth = 1, bricks = {
	brick("saw", 0, 0, { ability = "saw" }),
	brick("output", 0, 3, { port = "output" }),
} } } }
local MILL = { id = "d2", name = "Mill", versions = { { width = 1, depth = 1, bricks = {
	brick("sawbench", 0, 0, { ability = "sawbench" }),
	brick("input", 0, 3, { port = "input" }),
} } } }

local function place(ctx, design, x, y)
	return Placement.build(ctx, { design = design, version = 1, facing = "N", tileX = x, tileY = y })
end

local function endpoint(b, port)
	return { building = b, store = port.buffer, x = port.x, y = port.y }
end

local function setup()
	local ctx = Session.new(World.new(20, 20), Config, 1)
	ctx.dt = STEP
	local cutter = place(ctx, CUTTER, 2, 2)
	local mill = place(ctx, MILL, 10, 2)
	local v = Session.newVillager(1, 5.5 * TILE, 8.5 * TILE, Config)
	table.insert(ctx.pools.villagers, v)
	return ctx, cutter, mill, v
end

local function run(ctx, job, v, steps)
	for _ = 1, steps do
		if job.dead then
			return
		end
		Walker.step(v, ctx)
		Haul.step(job, ctx)
	end
end

test("a haul carries logs from an output buffer to an input buffer, then ends", function()
	local ctx, cutter, mill, v = setup()
	local out, inp = cutter.ports[1], mill.ports[1]
	for _ = 1, 3 do
		Storage.add(out.buffer, "log")
	end

	local job = Haul.new("log", 2, endpoint(cutter, out), endpoint(mill, inp))
	assertEqual(1, Storage.available(out.buffer, "log"), "the source items are reserved")
	assertEqual(inp.buffer.capacity - 2, Storage.room(inp.buffer), "the destination room is reserved")

	assertTrue(Haul.start(job, v, ctx))
	assertEqual(job, v.job)
	run(ctx, job, v, 60 * 30)

	assertTrue(job.dead, "the job ended")
	assertEqual(nil, v.job)
	assertEqual(1, out.buffer.counts.log)
	assertEqual(2, inp.buffer.counts.log)
	assertTrue(Load.empty(v.load))
	assertEqual(1, Storage.available(out.buffer, "log"), "no reservation left on the source")
	assertEqual(inp.buffer.capacity - 2, Storage.room(inp.buffer), "no room left reserved")
end)

test("a haul with no route to its source ends at once and releases its reservations", function()
	local ctx, cutter, mill, v = setup()
	local out, inp = cutter.ports[1], mill.ports[1]
	Storage.add(out.buffer, "log")
	for y = out.y - 1, out.y + 1 do
		for x = out.x - 1, out.x + 1 do
			if not (x == out.x and y == out.y) then
				World.setTerrain(ctx.world, x, y, "water")
			end
		end
	end

	local job = Haul.new("log", 1, endpoint(cutter, out), endpoint(mill, inp))
	assertFalse(Haul.start(job, v, ctx))
	assertTrue(job.dead)
	assertEqual(nil, v.job)
	assertEqual(1, Storage.available(out.buffer, "log"))
	assertEqual(inp.buffer.capacity, Storage.room(inp.buffer))
end)

test("a haul whose destination building is gone ends; the villager keeps its load", function()
	local ctx, cutter, mill, v = setup()
	local out, inp = cutter.ports[1], mill.ports[1]
	Storage.add(out.buffer, "log")
	Storage.add(out.buffer, "log")

	local job = Haul.new("log", 2, endpoint(cutter, out), endpoint(mill, inp))
	assertTrue(Haul.start(job, v, ctx))
	for _ = 1, 60 * 30 do
		Walker.step(v, ctx)
		Haul.step(job, ctx)
		if job.stage == "toDest" then
			break
		end
	end
	assertEqual(2, v.load.count)
	mill.dead = true
	Haul.step(job, ctx)
	assertTrue(job.dead)
	assertEqual(nil, v.job)
	assertEqual(2, v.load.count, "the load stays with the villager")
	assertEqual(inp.buffer.capacity, Storage.room(inp.buffer))
end)
