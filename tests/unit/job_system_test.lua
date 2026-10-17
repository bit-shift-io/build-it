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

-- pick: tiers (lingering on the task, free, lingering elsewhere).
local JobSystem = require("src.game.systems.job_system")

local function pv(x, y, linger)
	return { x = (x + 0.5) * TILE, y = (y + 0.5) * TILE, linger = linger }
end

local TASK = { kind = "operate", brick = {} }
local function lingerOn(task)
	return { task = task, anchor = {} }
end

test("pick takes the villager lingering on the task over a nearer free one", function()
	local near, mine = pv(5, 5), pv(20, 20, lingerOn(TASK))
	local free = { near, mine }
	assertEqual(mine, JobSystem.pick(free, TASK, 5, 5, TILE))
	assertEqual(1, #free)
	assertEqual(nil, mine.linger, "taking the villager clears its linger")
end)

test("pick prefers a free villager to one lingering elsewhere, whatever the distance", function()
	local other = lingerOn({ kind = "operate", brick = {} })
	local near, far = pv(5, 5, other), pv(25, 25)
	assertEqual(far, JobSystem.pick({ near, far }, TASK, 5, 5, TILE))
	assertEqual(far, JobSystem.pick({ near, far }, nil, 5, 5, TILE))
end)

test("pick falls back to a villager lingering elsewhere, nearest first, ties in pool order", function()
	local other = lingerOn({ kind = "operate", brick = {} })
	local a, b, c = pv(10, 5, other), pv(10, 5, other), pv(20, 5, other)
	local free = { c, a, b }
	assertEqual(a, JobSystem.pick(free, TASK, 5, 5, TILE))
	assertEqual(b, JobSystem.pick(free, TASK, 5, 5, TILE))
	assertEqual(c, JobSystem.pick(free, TASK, 5, 5, TILE))
end)

test("a loaded harvester keeps its linger on the way to storage", function()
	local ctx = newCtx()
	place(ctx, DEPOT, 10, 10)
	local v = villager(ctx, 4, 4)
	local anchor = place(ctx, MILL, 20, 20)
	v.linger = { task = TASK, anchor = anchor }
	v.load.item, v.load.count = "log", 1
	run(ctx, STEP)
	assertTrue(v.job ~= nil, "it took the storage haul")
	assertEqual(anchor, v.linger.anchor)
end)

-- Haul and build tasks.
local function haulTask(item, source, dest)
	return { kind = "haul", item = item, source = source, dest = dest }
end

test("pick matches a haul task on item, source building and destination building only", function()
	local src, dst = {}, {}
	local same = pv(20, 20, lingerOn(haulTask("log", src, dst)))
	local wrongItem = pv(5, 6, lingerOn(haulTask("plank", src, dst)))
	local wrongDest = pv(5, 7, lingerOn(haulTask("log", src, {})))
	local near = pv(5, 5)
	assertEqual(same, JobSystem.pick({ near, wrongItem, wrongDest, same }, haulTask("log", src, dst), 5, 5, TILE))
	assertEqual(near, JobSystem.pick({ wrongItem, near, wrongDest }, haulTask("log", src, dst), 5, 5, TILE))
end)

test("a finished build job's villager is first pick for any build task", function()
	local mine = pv(20, 20, lingerOn({ kind = "build" }))
	local near = pv(5, 5)
	assertEqual(mine, JobSystem.pick({ near, mine }, { kind = "build" }, 5, 5, TILE))
end)

local function lingerOf(v)
	return v.linger
end

test("a villager lingers on the haul route after a trip, a nearer free villager loses the next one", function()
	local ctx = newCtx()
	local cutter = place(ctx, CUTTER, 2, 2)
	local mill = place(ctx, MILL, 12, 2)
	local first = villager(ctx, 4, 6)
	fill(cutter.ports[1].buffer, "log", 1)
	run(ctx, 20)
	assertEqual(1, mill.ports[1].buffer.counts.log)
	local l = assert(lingerOf(first), "lingers after the haul")
	assertEqual("haul", l.task.kind)
	assertEqual("log", l.task.item)
	assertEqual(cutter, l.task.source)
	assertEqual(mill, l.task.dest)
	assertEqual(cutter, l.anchor)

	local second = villager(ctx, 12, 6) -- nearer to the cutter's port than first? no: far side
	second.x, second.y = cutter.ports[1].x * TILE + TILE / 2, (cutter.ports[1].y + 1) * TILE + TILE / 2
	mill.ports[1].buffer.counts.log = nil
	fill(cutter.ports[1].buffer, "log", 1)
	run(ctx, STEP)
	assertEqual(first.job, ctx.pools.jobs[#ctx.pools.jobs], "the lingering villager took it")
	assertEqual(nil, second.job)
end)

test("a hauled-off load with no source leaves no linger", function()
	local ctx = newCtx()
	place(ctx, DEPOT, 10, 10)
	local v = villager(ctx, 4, 4)
	v.load.item, v.load.count = "log", 1
	run(ctx, 20)
	assertEqual(nil, v.linger)
end)

test("a finished build job lingers beside the new building and takes the next build first", function()
	local ctx = newCtx()
	local store = place(ctx, STORE, 4, 2)
	store.storage.capacity = 100
	fill(store.storage, "plank", 40)
	local siteA = assert(Placement.place(ctx, { design = HALL, version = 1, facing = "N", tileX = 12, tileY = 2 }))
	local v = villager(ctx, 4, 0)
	local built = false
	for _ = 1, 60 * 120 do
		Session.advance(ctx, STEP)
		if siteA.dead then
			built = true
			break
		end
	end
	assertTrue(built, "site built")
	run(ctx, STEP * 2)
	local l = assert(v.linger, "builder lingers")
	assertEqual("build", l.task.kind)
	assertEqual(siteA.tileX, l.anchor.tileX)
	assertEqual(nil, l.anchor.dead)
end)

-- Experience: weighted distance within tiers 2 and 3.
local EXP = Config.villagers.experience

local function xpv(x, y, xp, linger)
	local v = pv(x, y, linger)
	v.xp = xp
	return v
end

test("pick: an experienced villager slightly farther beats a nearer novice", function()
	local novice, expert = xpv(5, 6, {}), xpv(5, 8, { haul = EXP.cap })
	assertEqual(expert, JobSystem.pick({ novice, expert }, { kind = "haul" }, 5, 5, TILE, EXP))
end)

test("pick: a novice much nearer still beats an experienced villager", function()
	local novice, expert = xpv(5, 5, {}), xpv(5, 5 + EXP.bonusTiles + 3, { haul = EXP.cap })
	assertEqual(novice, JobSystem.pick({ expert, novice }, { kind = "haul" }, 5, 5, TILE, EXP))
end)

test("pick: only experience in the task's own role counts; operators use the brick's ability", function()
	local hauler, sawyer = xpv(5, 7, { haul = EXP.cap }), xpv(5, 7, { saw = EXP.cap })
	local task = { kind = "operate", brick = { ability = "saw" } }
	assertEqual(sawyer, JobSystem.pick({ hauler, sawyer }, task, 5, 5, TILE, EXP))
end)

test("pick: experience past the cap earns nothing more", function()
	local a, b = xpv(5, 8, { build = EXP.cap }), xpv(5, 8, { build = EXP.cap * 5 })
	local near = xpv(5, 7, {})
	assertEqual(a, JobSystem.pick({ near, a, b }, { kind = "build" }, 5, 5, TILE, EXP))
	assertEqual(near, JobSystem.pick({ near, xpv(5, 12, { build = EXP.cap * 5 }) }, { kind = "build" }, 5, 5, TILE, EXP))
end)

test("pick: lingering on the task beats any experience", function()
	local mine = xpv(30, 30, {}, lingerOn({ kind = "build" }))
	local expert = xpv(5, 5, { build = EXP.cap })
	assertEqual(mine, JobSystem.pick({ expert, mine }, { kind = "build" }, 5, 5, TILE, EXP))
end)

local MILL_OUT = { id = "d9", name = "Mill", versions = { { width = 1, depth = 1, bricks = {
	brick("sawbench", 0, 0, { ability = "sawbench" }),
	brick("input", 0, 3, { port = "input" }),
	brick("output", 2, 3, { port = "output" }),
} } } }

test("a saw with a tree in reach and a saw bench with logs each get an operator", function()
	local ctx = newCtx()
	local cutter = place(ctx, CUTTER, 5, 5)
	local mill = place(ctx, MILL_OUT, 15, 5)
	World.addNode(ctx.world, { id = 1, kind = "tree", tileX = 5, tileY = 3, variant = 1, stage = 1, amount = 5 })
	fill(mill.ports[1].buffer, "log", 2)
	villager(ctx, 10, 12)
	villager(ctx, 11, 12)
	run(ctx, 3)
	assertTrue(cutter.functionBricks[1].operator ~= nil, "the saw has an operator")
	assertTrue(mill.functionBricks[1].operator ~= nil, "the saw bench has an operator")
end)
