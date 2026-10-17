-- The job system (src/game/systems/job_system.lua, docs/CONTEXT.md "Job",
-- "Haul job"): haul jobs come from world state each step and free
-- villagers take them, nearest first, one villager per job.
local Session = require("src.game.session")
local World = require("src.game.world")
local Config = require("src.game.config")
local Placement = require("src.game.buildings.placement")
local Storage = require("src.game.components.storage")
local StorageFacility = require("src.game.components.storage_facility")

local TILE = Config.tileSize
local STEP = 1 / 60

local function brick(shape, x, y, extra)
	local b = { x = x, y = y, z = 0, width = 2, depth = 1, height = 1, shape = shape, rotation = 0, material = "plank", paint = 1 }
	for k, v in pairs(extra or {}) do
		b[k] = v
	end
	return b
end

-- 1x1 tile buildings with their ports on the south edge. The cutter's saw
-- has no trees in reach, so it never adds logs of its own.
local CUTTER = { id = "d1", name = "Cutter", versions = { { width = 1, depth = 1, bricks = {
	brick("saw", 0, 0, { ability = "saw" }),
	brick("output", 0, 3, { port = "output" }),
} } } }
local MILL = { id = "d2", name = "Mill", versions = { { width = 1, depth = 1, bricks = {
	brick("sawbench", 0, 0, { ability = "sawbench" }),
	brick("input", 0, 3, { port = "input" }),
} } } }
-- Storage facilities: DEPOT takes drop-offs at its input port tile, STORE
-- also gives pick-ups at its output port tile.
local DEPOT = { id = "d3", name = "Depot", versions = { { width = 1, depth = 1, bricks = {
	brick("depot", 0, 0, { ability = "depot" }),
	brick("storage", 2, 0, { storage = 8 }),
	brick("input", 0, 3, { port = "input" }),
} } } }
local STORE = { id = "d5", name = "Store", versions = { { width = 1, depth = 1, bricks = {
	brick("depot", 0, 0, { ability = "depot" }),
	brick("storage", 2, 0, { storage = 8 }),
	brick("input", 0, 3, { port = "input" }),
	brick("output", 2, 3, { port = "output" }),
} } } }

local function place(ctx, design, x, y)
	return Placement.build(ctx, { design = design, version = 1, facing = "N", tileX = x, tileY = y })
end

local function villager(ctx, tileX, tileY)
	local v = Session.newVillager(#ctx.pools.villagers + 1, (tileX + 0.5) * TILE, (tileY + 0.5) * TILE, Config)
	table.insert(ctx.pools.villagers, v)
	return v
end

local function newCtx()
	return Session.new(World.new(30, 30), Config, 1)
end

local function run(ctx, seconds)
	for _ = 1, math.floor(seconds / STEP + 0.5) do
		Session.advance(ctx, STEP)
	end
end

local function fill(store, item, n)
	for _ = 1, n do
		Storage.add(store, item)
	end
end

test("a log in a woodcutter's output is hauled to a sawmill input with room", function()
	local ctx = newCtx()
	local cutter = place(ctx, CUTTER, 2, 2)
	local mill = place(ctx, MILL, 12, 2)
	villager(ctx, 6, 8)
	fill(cutter.ports[1].buffer, "log", 1)

	run(ctx, 20)
	assertEqual(nil, cutter.ports[1].buffer.counts.log)
	assertEqual(1, mill.ports[1].buffer.counts.log)
end)

test("without a sawmill, a woodcutter's logs are hauled to the nearest storage facility with room", function()
	local ctx = newCtx()
	local cutter = place(ctx, CUTTER, 2, 2)
	local far = place(ctx, DEPOT, 25, 2)
	local near = place(ctx, DEPOT, 8, 2)
	local full = place(ctx, DEPOT, 4, 2)
	fill(full.storage, "stone", full.storage.capacity)
	villager(ctx, 6, 8)
	fill(cutter.ports[1].buffer, "log", 3)

	run(ctx, 20)
	assertEqual(nil, cutter.ports[1].buffer.counts.log)
	assertEqual(3, near.storage.counts.log)
	assertEqual(nil, far.storage.counts.log)
end)

test("logs in storage feed a sawmill input once one exists", function()
	local ctx = newCtx()
	local store = place(ctx, STORE, 4, 2)
	fill(store.storage, "log", 1)
	villager(ctx, 6, 8)
	run(ctx, 2)
	assertEqual(1, StorageFacility.totals(ctx).log, "nothing consumes logs yet")

	local mill = place(ctx, MILL, 12, 2)
	run(ctx, 20)
	assertEqual(nil, StorageFacility.totals(ctx).log)
	assertEqual(1, mill.ports[1].buffer.counts.log)
end)

test("a sawmill input is fed from an output or storage, whichever is nearer", function()
	for _, case in ipairs({ { cutterX = 10, storeX = 20, nearer = "cutter" }, { cutterX = 20, storeX = 10, nearer = "store" } }) do
		local ctx = newCtx()
		local mill = place(ctx, MILL, 14, 2)
		local cutter = place(ctx, CUTTER, case.cutterX, 2)
		local store = place(ctx, STORE, case.storeX, 2)
		fill(cutter.ports[1].buffer, "log", 1)
		fill(store.storage, "log", 1)
		fill(store.storage, "stone", store.storage.capacity - 1) -- no room for the cutter's log
		villager(ctx, 15, 8)

		run(ctx, 0.1)
		local job = ctx.pools.jobs[1]
		assertEqual(mill.ports[1].buffer, job.dest.store)
		assertEqual(case.nearer == "cutter" and cutter or store, job.source.building, case.nearer .. " is nearer")
	end
end)

test("two free villagers never take the same items; the nearer one wins", function()
	local ctx = newCtx()
	local cutter = place(ctx, CUTTER, 2, 2)
	local mill = place(ctx, MILL, 12, 2)
	local far = villager(ctx, 20, 20)
	local near = villager(ctx, 4, 5)
	fill(cutter.ports[1].buffer, "log", 1)

	run(ctx, STEP)
	assertEqual(1, #ctx.pools.jobs)
	assertEqual(near, ctx.pools.jobs[1].villager)
	assertEqual(nil, far.job)

	run(ctx, 20)
	assertEqual(1, mill.ports[1].buffer.counts.log)
	assertEqual(nil, far.job)
end)

test("a busy villager is never pulled off its job for a nearer one", function()
	local ctx = newCtx()
	local cutter = place(ctx, CUTTER, 2, 2)
	local other = place(ctx, CUTTER, 2, 20)
	place(ctx, MILL, 25, 2)
	place(ctx, MILL, 25, 20)
	local busy = villager(ctx, 3, 4)
	fill(cutter.ports[1].buffer, "log", 1)
	run(ctx, STEP)
	local job = busy.job
	assertTrue(job ~= nil)
	run(ctx, 1) -- carrying, heading east

	local free = villager(ctx, 28, 28)
	busy.x, busy.y = (2 + 0.5) * TILE, (21 + 0.5) * TILE -- now right beside the new log
	fill(other.ports[1].buffer, "log", 1)
	run(ctx, STEP)
	assertEqual(job, busy.job)
	assertTrue(free.job ~= nil, "the free villager took the new job")
	assertEqual(other.ports[1].buffer, free.job.source.store)
end)

-- A storage facility with an output port on the south edge.
local SHOP = { id = "d4", name = "Shop", versions = { { width = 1, depth = 1, bricks = {
	brick("depot", 0, 0, { ability = "depot" }),
	brick("storage", 2, 0, { storage = 8 }),
	brick("output", 0, 3, { port = "output" }),
} } } }

test("logs a hauler reserved in storage stay there for it, not flushed to the output", function()
	local ctx = newCtx()
	local shop = place(ctx, SHOP, 4, 2)
	local out = shop.ports[1]
	fill(out.buffer, "stone", out.buffer.capacity)
	fill(shop.storage, "log", 1)
	local mill = place(ctx, MILL, 12, 2)
	villager(ctx, 20, 20)
	run(ctx, STEP)
	assertEqual(shop.storage, ctx.pools.jobs[1].source.store)

	out.buffer.counts = {} -- the player collected the stone
	run(ctx, STEP)
	assertEqual(1, shop.storage.counts.log, "the reserved log stayed in storage")
	run(ctx, 30)
	assertEqual(1, mill.ports[1].buffer.counts.log)
end)

test("a free villager carrying a load takes it to the nearest storage facility", function()
	local ctx = newCtx()
	local store = place(ctx, DEPOT, 4, 2)
	local v = villager(ctx, 20, 20)
	v.load.item, v.load.count = "log", 3

	run(ctx, 30)
	assertEqual(3, store.storage.counts.log)
	assertEqual(0, v.load.count)
end)

local function portOf(b, kind)
	for _, p in ipairs(b.ports) do
		if p.kind == kind then
			return p
		end
	end
end

test("a loaded villager drops off at the facility's input port tile, into its storage", function()
	local ctx = newCtx()
	local store = place(ctx, DEPOT, 4, 2)
	local v = villager(ctx, 4, 0) -- north of the facility, away from its port
	v.load.item, v.load.count = "log", 3

	run(ctx, STEP)
	local dest, input = v.job.dest, portOf(store, "input")
	assertEqual(input.x, dest.x)
	assertEqual(input.y, dest.y)
	assertEqual(store.storage, dest.store)
end)

test("a sawmill input fed from a facility's storage is picked up at its output port tile", function()
	local ctx = newCtx()
	local store = place(ctx, STORE, 4, 2)
	local output = portOf(store, "output")
	fill(output.buffer, "stone", output.buffer.capacity) -- keeps the log in storage
	fill(store.storage, "log", 1)
	place(ctx, MILL, 12, 2)
	villager(ctx, 4, 0)

	run(ctx, STEP)
	local source = ctx.pools.jobs[1].source
	assertEqual(store.storage, source.store)
	assertEqual(output.x, source.x)
	assertEqual(output.y, source.y)
end)

-- A 2x1 hall with no function bricks: placing it leaves a site.
local HALL = { id = "d6", name = "Hall", versions = { { width = 2, depth = 1, bricks = {
	brick("2x2", 0, 0),
} } } }

test("a site is supplied from a facility's storage at its output port tile, keeping the claim", function()
	local ctx = newCtx()
	local store = place(ctx, STORE, 4, 2)
	store.storage.capacity = 100
	fill(store.storage, "plank", 20)
	local site = assert(Placement.place(ctx, { design = HALL, version = 1, facing = "N", tileX = 12, tileY = 2 }))
	villager(ctx, 4, 0)

	run(ctx, STEP)
	local job, output = ctx.pools.jobs[1], portOf(store, "output")
	assertEqual(site, job.dest.building)
	assertEqual(output.x, job.source.x)
	assertEqual(output.y, job.source.y)
	assertEqual(site.claims[1], job.source.claim)
end)

test("a facility with no input port takes no drop-offs; one with no output port gives no pick-ups", function()
	local ctx = newCtx()
	local closed = place(ctx, { id = "d7", name = "Closed", versions = { { width = 1, depth = 1, bricks = {
		brick("depot", 0, 0, { ability = "depot" }),
		brick("storage", 2, 0, { storage = 8 }),
	} } } }, 4, 2)
	fill(closed.storage, "log", 1)
	place(ctx, MILL, 12, 2)
	local v = villager(ctx, 4, 4)
	v.load.item, v.load.count = "stone", 1

	run(ctx, 1)
	assertEqual(0, #ctx.pools.jobs)
	assertEqual(1, closed.storage.counts.log)
	assertEqual(nil, closed.storage.counts.stone)
end)

-- A 2x1 facility with an input port under each tile of its south edge.
local WIDE = { id = "d8", name = "Wide", versions = { { width = 2, depth = 1, bricks = {
	brick("depot", 0, 0, { ability = "depot" }),
	brick("storage", 2, 0, { storage = 8 }),
	brick("input", 0, 3, { port = "input" }),
	brick("input", 4, 3, { port = "input" }),
} } } }

test("a hauler drops off at the input port tile nearest it, ties to the first port", function()
	for _, case in ipairs({ { x = 4, port = 1 }, { x = 9, port = 2 } }) do
		local ctx = newCtx()
		local store = place(ctx, WIDE, 4, 2)
		local v = villager(ctx, case.x, 0)
		v.load.item, v.load.count = "log", 1

		run(ctx, STEP)
		assertEqual(store.ports[case.port].x, v.job.dest.x, "from x " .. case.x)
	end
end)
