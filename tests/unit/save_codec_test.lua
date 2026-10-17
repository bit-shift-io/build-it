-- The world save codec (src/game/save/codec.lua): a session turns into the
-- text of the save file and back, and a loaded session steps exactly like
-- the one it was saved from.
local Session = require("src.game.session")
local World = require("src.game.world")
local Config = require("src.game.config")
local SaveCodec = require("src.game.save.codec")

local STEP = 1 / 60

local function run(ctx, seconds)
	for _ = 1, math.floor(seconds / STEP + 0.5) do
		Session.advance(ctx, STEP)
	end
end

local function roundTrip(ctx)
	local text = SaveCodec.encode(ctx)
	local loaded, reason = SaveCodec.decode(text, Config)
	assertTrue(loaded ~= nil, "expected the save to load: " .. tostring(reason))
	return loaded
end

test("the character, session clock, seed and rng state round-trip", function()
	local ctx = Session.new(World.new(20, 20), Config, 7)
	ctx.intents[1] = { x = 1, y = 0.5 }
	run(ctx, 0.5)
	ctx.rng:next()
	local c = ctx.pools.characters[1]
	c.inventory.counts.log = 3

	local loaded = roundTrip(ctx)
	local lc = loaded.pools.characters[1]
	assertEqual(7, loaded.seed)
	assertEqual(ctx.time, loaded.time)
	assertEqual(ctx.rng.state, loaded.rng.state)
	assertEqual(ctx.rng:next(), loaded.rng:next())
	assertEqual(c.x, lc.x)
	assertEqual(c.y, lc.y)
	assertEqual(3, lc.inventory.counts.log)
	assertEqual(c.inventory.counts.plank, lc.inventory.counts.plank)
	assertEqual(c.animator.facing, lc.animator.facing)
	assertEqual(c.animator.frame, lc.animator.frame)
	assertEqual(c.animator.distance, lc.animator.distance)
end)

test("terrain and nodes (amount, stage, growth) round-trip, tile index rebuilt", function()
	local world = World.new(20, 20)
	World.setTerrain(world, 3, 4, "water")
	World.setTerrain(world, 19, 19, "water")
	World.addNode(world, { id = 1, kind = "tree", tileX = 5, tileY = 5, variant = 2, stage = 2, amount = 4 })
	World.addNode(world, { id = 2, kind = "tree", tileX = 6, tileY = 5, variant = 3, stage = 5, amount = 10, growing = 61.25 })
	World.addNode(world, { id = 7, kind = "rock", tileX = 0, tileY = 0, variant = 8, stage = 1, amount = 6 })
	local ctx = Session.new(world, Config, 1)
	ctx.nextNodeId = 8

	local loaded = roundTrip(ctx)
	assertEqual("water", World.terrainAt(loaded.world, 3, 4))
	assertEqual("water", World.terrainAt(loaded.world, 19, 19))
	assertEqual("grass", World.terrainAt(loaded.world, 4, 4))
	assertEqual(3, #loaded.pools.nodes)
	assertTrue(loaded.pools.nodes == loaded.world.nodes, "expected the node pool to be the world's")
	for i, n in ipairs(ctx.pools.nodes) do
		local ln = loaded.pools.nodes[i]
		for _, key in ipairs({ "id", "kind", "tileX", "tileY", "variant", "stage", "amount", "growing" }) do
			assertEqual(n[key], ln[key], key .. " of node " .. n.id)
		end
		assertTrue(World.nodeAt(loaded.world, n.tileX, n.tileY) == ln, "expected node " .. n.id .. " on its tile")
	end
	assertEqual(8, loaded.nextNodeId)
end)

local Placement = require("src.game.buildings.placement")
local Inventory = require("src.game.components.inventory")
local Storage = require("src.game.components.storage")
local NodeSystem = require("src.game.systems.node_system")

local function brick(shape, x, y, f)
	return { x = x, y = y, z = 0, width = f.width, depth = f.depth, height = 1, shape = shape, rotation = 0, material = "plank", paint = 1, ability = f.ability, port = f.port, storage = f.storage }
end

-- A 2x1 tile works: a saw, a saw bench, storage, and an input and an output
-- port on the south edge.
local function works()
	return { id = "d3", name = "Works", versions = { {
		width = 2,
		depth = 1,
		bricks = {
			brick("saw", 0, 0, { width = 4, depth = 2, ability = "saw" }),
			brick("sawbench", 4, 0, { width = 4, depth = 2, ability = "sawbench" }),
			brick("storage", 0, 2, { width = 2, depth = 1, storage = 8 }),
			brick("input", 0, 3, { width = 2, depth = 1, port = "input" }),
			brick("output", 4, 3, { width = 2, depth = 1, port = "output" }),
		},
	} } }
end

-- A session with a working, part-filled works facing E beside a few trees.
local function busySession()
	local world = World.new(30, 30)
	for i = 1, 4 do
		World.addNode(world, { id = i, kind = "tree", tileX = 8 + i, tileY = 8, variant = i, stage = 1, amount = Config.nodes.tree.amount })
	end
	local ctx = Session.new(world, Config, 3)
	local c = ctx.pools.characters[1]
	c.inventory = Inventory.new({ plank = 10000, stone = 10000, log = 5 })
	local b = assert(Placement.build(ctx, { design = works(), version = 1, facing = "E", tileX = 10, tileY = 10 }))
	for _, port in ipairs(b.ports) do
		if port.kind == "input" then
			Storage.add(port.buffer, "log")
		end
	end
	run(ctx, 7.3)
	return ctx, b
end

test("buildings round-trip with their facing, buffers, storage, function bricks and reservations", function()
	local ctx, b = busySession()
	NodeSystem.reserve(ctx.pools.nodes[1], b.functionBricks[1]) -- as an operator would
	b.functionBricks[1].progress = 1.25

	local loaded = roundTrip(ctx)
	assertEqual(1, #loaded.pools.buildings)
	local lb = loaded.pools.buildings[1]
	for _, key in ipairs({ "id", "version", "facing", "tileX", "tileY", "width", "depth", "full" }) do
		assertEqual(b[key], lb[key], key)
	end
	assertEqual("d3", lb.design.id)
	assertEqual(b.traits.productivity, lb.traits.productivity)
	assertEqual(Storage.total(b.storage), Storage.total(lb.storage))
	assertEqual(b.storage.capacity, lb.storage.capacity)
	for item, n in pairs(b.storage.counts) do
		assertEqual(n, lb.storage.counts[item], "storage " .. item)
	end
	assertEqual(#b.ports, #lb.ports)
	for i, port in ipairs(b.ports) do
		local lp = lb.ports[i]
		assertEqual(port.kind, lp.kind)
		assertTrue(lp.building == lb, "expected the port's back-reference rebuilt")
		assertTrue(World.portAt(loaded.world, lp.x, lp.y) == lp, "expected the port tile index rebuilt")
		assertEqual(Storage.total(port.buffer), Storage.total(lp.buffer), "buffer " .. i)
		for item, n in pairs(port.buffer.counts) do
			assertEqual(n, lp.buffer.counts[item], "buffer " .. i .. " " .. item)
		end
	end
	assertTrue(World.buildingAt(loaded.world, lb.tileX, lb.tileY) == lb, "expected the footprint index rebuilt")
	for i, fb in ipairs(b.functionBricks) do
		local lfb = lb.functionBricks[i]
		assertEqual(fb.ability, lfb.ability)
		assertEqual(fb.progress, lfb.progress, "progress of " .. fb.ability)
		assertEqual(fb.state, lfb.state, "state of " .. fb.ability)
		if fb.node then
			assertEqual(fb.node.id, lfb.node.id)
			assertTrue(lfb.node.reservedBy == lfb, "expected the reservation rebuilt both ways")
		else
			assertEqual(nil, lfb.node)
		end
	end
end)

local function forester()
	return { id = "d4", name = "Forester", versions = { { width = 2, depth = 1, bricks = {
		brick("planter", 0, 0, { width = 4, depth = 2, ability = "planter" }),
	} } } }
end

test("a loaded session steps exactly like the session it was saved from", function()
	local ctx = busySession()
	local c = ctx.pools.characters[1]
	assert(Placement.build(ctx, { design = forester(), version = 1, facing = "N", tileX = 20, tileY = 20 }))
	-- Stand beside tree 4 (tile 12, 8) and hand-harvest it.
	c.x, c.y = 12.5 * Config.tileSize, 9.2 * Config.tileSize
	ctx.intents[1] = { x = 0, y = 0, harvest = true }
	run(ctx, 1.3)
	assertTrue(c.harvester.node ~= nil and c.harvester.progress > 0, "fixture: expected a hand harvest under way")

	local loaded = roundTrip(ctx)
	for _, session in ipairs({ ctx, loaded }) do
		-- A villager operates the planter (operators are not saved, so it joins after the load).
		-- The first takes the saw bench, the second the planter.
		for i = 1, 2 do
			table.insert(session.pools.villagers, Session.newVillager(i, (18 + i) * Config.tileSize, 19.5 * Config.tileSize, Config))
		end
		session.intents[1] = { x = 0.3, y = -1, harvest = true }
		run(session, 0.4)
		session.intents[1] = { x = 0, y = 0, harvest = true }
		run(session, 30)
	end
	assertTrue(#ctx.pools.nodes > 4, "fixture: expected the planter to have planted")
	assertEqual(SaveCodec.encode(ctx), SaveCodec.encode(loaded))
end)

test("a building's design version loads from the save's own snapshot", function()
	local ctx, b = busySession()
	local text = SaveCodec.encode(ctx)
	local original = works().versions[1]
	b.design.versions = {} -- the library lost the design: nothing else to read it from

	local loaded = assert(SaveCodec.decode(text, Config))
	local lb = loaded.pools.buildings[1]
	assertEqual("Works", lb.design.name)
	local version = lb.design.versions[1]
	assertEqual(original.width, version.width)
	assertEqual(original.depth, version.depth)
	assertEqual(nil, version.n)
	assertEqual(#original.bricks, #version.bricks)
	for i, brick in ipairs(original.bricks) do
		for key, value in pairs(brick) do
			assertEqual(value, version.bricks[i][key], key .. " of brick " .. i)
		end
	end
end)

test("text that is not a readable save is refused with a reason", function()
	local ctx = busySession()
	local good = SaveCodec.encode(ctx)
	for _, text in ipairs({
		"",
		"build-it-design 1\n",
		good:gsub("design=s:d3", "design=s:d9"),
		good:gsub("\nworld [^\n]*", ""),
		good .. "mystery a=n:1\n",
	}) do
		local loaded, reason = SaveCodec.decode(text, Config)
		assertEqual(nil, loaded)
		assertEqual("string", type(reason))
	end
end)

test("a save from format 1 is refused as too old", function()
	local text = SaveCodec.encode(Session.new(World.new(20, 20), Config, 1))
	local old = text:gsub("^build%-it%-save %d+", "build-it-save 1")

	local loaded, reason = SaveCodec.decode(old, Config)
	assertEqual(nil, loaded)
	assertTrue(tostring(reason):find("older") ~= nil, "expected an older-format reason, got " .. tostring(reason))
end)

local Starter = require("src.game.designs.starter")
local WorldGen = require("src.game.world_gen")

test("a new game round-trips: the starter facility, its design snapshot and its stored stockpile", function()
	local ctx = Session.newGame(WorldGen.generate(Config, 1), Config, 1)
	run(ctx, 0.5)

	local loaded = roundTrip(ctx)
	local b, lb = ctx.pools.buildings[1], loaded.pools.buildings[1]
	assertEqual(Starter.ID, lb.design.id)
	assertEqual(#b.design.versions[1].bricks, #lb.design.versions[1].bricks)
	assertEqual(b.tileX, lb.tileX)
	assertEqual(b.tileY, lb.tileY)
	assertEqual(World.buildingAt(loaded.world, b.tileX, b.tileY), lb)
	for _, item in ipairs({ "plank", "stone" }) do
		assertEqual(b.storage.counts[item], lb.storage.counts[item], item .. " in storage")
		for i, port in ipairs(b.ports) do
			assertEqual(port.buffer.counts[item], lb.ports[i].buffer.counts[item], item .. " in port " .. i)
		end
	end
	assertEqual(SaveCodec.encode(ctx), SaveCodec.encode(loaded))
end)

local Walker = require("src.game.components.walker")

test("villagers round-trip with their position, animation and the rest of their walk path", function()
	local ctx = Session.newGame(WorldGen.generate(Config, 1), Config, 1)
	local v = ctx.pools.villagers[2]
	local b = ctx.pools.buildings[1]
	assertTrue(Walker.goTo(v, ctx, b.tileX - 4, b.tileY + 1))
	run(ctx, 0.3)
	assertTrue(#v.walker.path > 0, "still walking when saved")

	local loaded = roundTrip(ctx)
	assertEqual(#ctx.pools.villagers, #loaded.pools.villagers)
	for i, ov in ipairs(ctx.pools.villagers) do
		local lv = loaded.pools.villagers[i]
		assertEqual(ov.id, lv.id)
		assertEqual(ov.x, lv.x)
		assertEqual(ov.y, lv.y)
		assertEqual(ov.animator.facing, lv.animator.facing)
		assertEqual(ov.animator.frame, lv.animator.frame)
		assertEqual(ov.animator.distance, lv.animator.distance)
		assertEqual(nil, lv.mover.enter, "a loaded villager holds no job, so may enter no footprint")
		assertEqual(#ov.walker.path, #lv.walker.path)
		for k, p in ipairs(ov.walker.path) do
			assertEqual(p.x, lv.walker.path[k].x)
			assertEqual(p.y, lv.walker.path[k].y)
		end
	end
	run(ctx, 2)
	run(loaded, 2)
	assertEqual(v.x, loaded.pools.villagers[2].x)
	assertEqual(v.y, loaded.pools.villagers[2].y)
	-- Idle state (timers, phase) is not saved, so once the walk ends the two
	-- sessions draw different idle rolls: only the walk itself must match.
end)

test("a villager's load round-trips", function()
	local ctx = Session.new(World.new(20, 20), Config, 1)
	local v = Session.newVillager(1, 100, 100, Config)
	v.load.item, v.load.count = "log", 3
	local empty = Session.newVillager(2, 140, 100, Config)
	v.name, empty.name = "Ada", "Bram"
	ctx.pools.villagers = { v, empty }

	local loaded = roundTrip(ctx)
	local lv, le = loaded.pools.villagers[1], loaded.pools.villagers[2]
	assertEqual("log", lv.load.item)
	assertEqual(3, lv.load.count)
	assertEqual(Config.villagers.carryLimit, lv.load.limit)
	assertEqual(nil, le.load.item)
	assertEqual(0, le.load.count)
	assertEqual(SaveCodec.encode(ctx), SaveCodec.encode(loaded))
end)

-- Every log in a session: in storage, port buffers and villagers' loads.
local function logs(ctx)
	local n = 0
	for _, b in ipairs(ctx.pools.buildings) do
		n = n + (b.storage.counts.log or 0)
		for _, port in ipairs(b.ports) do
			n = n + (port.buffer.counts.log or 0)
		end
	end
	for _, v in ipairs(ctx.pools.villagers) do
		if v.load.item == "log" then
			n = n + v.load.count
		end
	end
	return n
end

test("saving and loading mid-haul loses no items; the hauler takes its load to storage", function()
	local ctx = Session.new(World.new(30, 30), Config, 1)
	local cutter = assert(Placement.build(ctx, { design = { id = "d5", name = "Cutter", versions = { { width = 1, depth = 1, bricks = {
		brick("saw", 0, 0, { width = 2, depth = 2, ability = "saw" }),
		brick("output", 0, 3, { width = 2, depth = 1, port = "output" }),
	} } } }, version = 1, facing = "N", tileX = 3, tileY = 3 }))
	local store = assert(Placement.build(ctx, { design = { id = "d6", name = "Store", versions = { { width = 1, depth = 1, bricks = {
		brick("depot", 0, 0, { width = 2, depth = 2, ability = "depot" }),
		brick("storage", 2, 0, { width = 2, depth = 2, storage = 8 }),
		brick("input", 0, 3, { width = 2, depth = 1, port = "input" }),
	} } } }, version = 1, facing = "N", tileX = 20, tileY = 3 }))
	for _ = 1, 3 do
		Storage.add(cutter.ports[1].buffer, "log")
	end
	local v = Session.newVillager(1, 4.5 * Config.tileSize, 6.5 * Config.tileSize, Config)
	ctx.pools.villagers = { v }
	for _ = 1, 60 * 30 do
		Session.advance(ctx, STEP)
		if v.load.count > 0 then
			break
		end
	end
	assertEqual(3, v.load.count, "fixture: saved while carrying")

	local loaded = roundTrip(ctx)
	assertEqual(3, logs(loaded))
	run(loaded, 30)
	assertEqual(3, logs(loaded))
	assertEqual(3, loaded.pools.buildings[2].storage.counts.log)
	assertEqual(0, loaded.pools.villagers[1].load.count)
	assertEqual(nil, store.storage.counts.log, "the original session is untouched")
end)

-- Logs in a session, with every plank counted as the 2 logs it was made of.
local function wood(ctx)
	local n = logs(ctx)
	local function planks(store)
		n = n + 2 * (store.counts.plank or 0)
	end
	for _, b in ipairs(ctx.pools.buildings) do
		planks(b.storage)
		for _, port in ipairs(b.ports) do
			planks(port.buffer)
		end
	end
	for _, v in ipairs(ctx.pools.villagers) do
		if v.load.item == "plank" then
			n = n + 2 * v.load.count
		end
	end
	return n
end

test("a converter's progress round-trips; its operator is dropped on load and keeps its load", function()
	local ctx = Session.new(World.new(30, 30), Config, 1)
	local mill = assert(Placement.build(ctx, { design = { id = "d7", name = "Mill", versions = { { width = 2, depth = 1, bricks = {
		brick("sawbench", 0, 0, { width = 4, depth = 2, ability = "sawbench" }),
		brick("input", 0, 3, { width = 2, depth = 1, port = "input" }),
		brick("output", 4, 3, { width = 2, depth = 1, port = "output" }),
	} } } }, version = 1, facing = "N", tileX = 5, tileY = 5 }))
	assert(Placement.build(ctx, { design = { id = "d6", name = "Store", versions = { { width = 1, depth = 1, bricks = {
		brick("depot", 0, 0, { width = 2, depth = 2, ability = "depot" }),
		brick("storage", 2, 0, { width = 2, depth = 2, storage = 8 }),
		brick("input", 0, 3, { width = 2, depth = 1, port = "input" }),
	} } } }, version = 1, facing = "N", tileX = 20, tileY = 5 }))
	for _ = 1, 4 do
		Storage.add(mill.ports[1].buffer, "log")
	end
	ctx.pools.villagers = { Session.newVillager(1, 6.5 * Config.tileSize, 8.5 * Config.tileSize, Config) }
	local fb = mill.functionBricks[1]
	for _ = 1, 60 * 30 do
		Session.advance(ctx, STEP)
		if fb.progress > 0.5 then
			break
		end
	end
	assertTrue(fb.operator ~= nil and fb.state == "working", "fixture: saved mid-cycle")

	local loaded = roundTrip(ctx)
	local lfb, lv = loaded.pools.buildings[1].functionBricks[1], loaded.pools.villagers[1]
	assertEqual(fb.progress, lfb.progress)
	assertEqual(fb.state, lfb.state)
	assertEqual(nil, lfb.operator)
	assertEqual(nil, lv.job)
	assertEqual("log", lv.load.item)
	assertEqual(2, lv.load.count)
	assertEqual(4, wood(loaded))
	run(loaded, 60)
	assertEqual(4, wood(loaded), "no wood lost")
	assertTrue((loaded.pools.buildings[2].storage.counts.plank or 0) > 0, "the loaded session goes on making planks")
end)

test("a harvester's node and progress round-trip; its operator is dropped on load and a new one carries on", function()
	local world = World.new(30, 30)
	World.addNode(world, { id = 1, kind = "tree", tileX = 9, tileY = 10, variant = 1, stage = 1, amount = Config.nodes.tree.amount })
	local ctx = Session.new(world, Config, 1)
	local b = assert(Placement.build(ctx, { design = { id = "d8", name = "Cutter", versions = { { width = 2, depth = 1, bricks = {
		brick("saw", 0, 0, { width = 3, depth = 1, ability = "saw" }),
		brick("output", 4, 3, { width = 2, depth = 1, port = "output" }),
	} } } }, version = 1, facing = "N", tileX = 10, tileY = 10 }))
	ctx.pools.villagers = { Session.newVillager(1, 6.5 * Config.tileSize, 10.5 * Config.tileSize, Config) }
	local fb = b.functionBricks[1]
	for _ = 1, 60 * 30 do
		Session.advance(ctx, STEP)
		if fb.progress > 0.5 and fb.operator and fb.operator.stage == "harvesting" and ctx.pools.villagers[1].load.count == 0 then
			break
		end
	end
	assertTrue(fb.operator ~= nil and fb.node ~= nil and fb.progress > 0.5, "fixture: saved mid-harvest")

	local loaded = roundTrip(ctx)
	local lfb, lv = loaded.pools.buildings[1].functionBricks[1], loaded.pools.villagers[1]
	assertEqual(fb.progress, lfb.progress)
	assertEqual(1, lfb.node.id)
	assertTrue(lfb.node.reservedBy == lfb)
	assertEqual(nil, lfb.operator)
	assertEqual(nil, lv.job)
	assertEqual(fb.node.amount, lfb.node.amount)

	run(loaded, 60)
	assertEqual(Config.production.bufferSize, loaded.pools.buildings[1].ports[1].buffer.counts.log, "the output fills again")
end)

local StorageFacility = require("src.game.components.storage_facility")
local Cost = require("src.game.builder.cost")

local HALL = { id = "d7", name = "Hall", versions = { { width = 2, depth = 1, bricks = {
	brick("1x1", 0, 0, { width = 1, depth = 1 }),
	brick("output", 6, 3, { width = 1, depth = 1, port = "output" }),
} } } }

local function siteSession()
	local ctx = Session.new(World.new(30, 30), Config, 1)
	local store = assert(Placement.build(ctx, { design = { id = "d6", name = "Store", versions = { { width = 1, depth = 1, bricks = {
		brick("depot", 0, 0, { width = 2, depth = 2, ability = "depot" }),
		brick("storage", 2, 0, { width = 2, depth = 2, storage = 8 }),
		brick("input", 0, 3, { width = 2, depth = 1, port = "input" }),
		brick("output", 2, 3, { width = 2, depth = 1, port = "output" }),
	} } } }, version = 1, facing = "N", tileX = 20, tileY = 3 }))
	store.storage.capacity = 1000
	local cost = Cost.of(HALL.versions[1], Config).plank
	for _ = 1, cost + 5 do
		Storage.add(store.storage, "plank")
	end
	local site = assert(Placement.place(ctx, { design = HALL, version = 1, facing = "N", tileX = 5, tileY = 5 }))
	return ctx, site, store, cost
end

test("a construction site round-trips with part of its materials delivered and its claims", function()
	local ctx, site, store, cost = siteSession()
	ctx.pools.villagers = { Session.newVillager(1, 6.5 * Config.tileSize, 7.5 * Config.tileSize, Config) }
	ctx.pools.villagers[1].name = "Ada"
	for _ = 1, 60 * 60 do
		Session.advance(ctx, STEP)
		local n = site.delivered.counts.plank or 0
		if n > 0 and ctx.pools.villagers[1].load.count == 0 then
			break
		end
	end
	local delivered = site.delivered.counts.plank or 0
	assertTrue(delivered > 0 and delivered < cost, "fixture: saved part delivered")

	local loaded = roundTrip(ctx)
	assertEqual(SaveCodec.encode(ctx), SaveCodec.encode(loaded))
	assertEqual(0, #loaded.pools.buildings - 1, "still a site")
	local ls = loaded.pools.sites[1]
	assertEqual(HALL.id, ls.design.id)
	assertEqual(5, ls.tileX)
	assertEqual(delivered, ls.delivered.counts.plank)
	assertEqual(cost, ls.cost.plank)
	assertTrue(World.buildingAt(loaded.world, 6, 5) == ls, "the footprint index rebuilt")
	local lstore = loaded.pools.buildings[1]
	assertEqual(store.storage.claimed.plank, lstore.storage.claimed.plank, "the claim rebuilt in storage")
	assertEqual(StorageFacility.totals(ctx).plank, StorageFacility.totals(loaded).plank)
	assertEqual(5, StorageFacility.totals(loaded).plank)

	for _ = 1, 60 * 120 do
		Session.advance(loaded, STEP)
		if #loaded.pools.sites == 0 then
			break
		end
	end
	assertEqual(0, #loaded.pools.sites, "the loaded site gets built")
	assertEqual(2, #loaded.pools.buildings)
	assertEqual(5, StorageFacility.totals(loaded).plank, "what the site left stays in the facility")
end)

test("a site's build progress round-trips", function()
	local ctx, site = siteSession()
	site.progress = 0.75

	local loaded = roundTrip(ctx)
	assertEqual(0.75, loaded.pools.sites[1].progress)
end)

test("villager experience round-trips; a format 2 save loads with empty experience", function()
	local ctx = Session.new(World.new(20, 20), Config, 1)
	local v = Session.newVillager(1, 40, 40, Config)
	v.xp.haul, v.xp.saw = 3, 25
	table.insert(ctx.pools.villagers, v)
	table.insert(ctx.pools.villagers, Session.newVillager(2, 60, 60, Config))

	local text = SaveCodec.encode(ctx)
	local loaded = roundTrip(ctx)
	assertEqual(3, loaded.pools.villagers[1].xp.haul)
	assertEqual(25, loaded.pools.villagers[1].xp.saw)
	assertEqual(nil, next(loaded.pools.villagers[2].xp))

	local old = text:gsub("^build%-it%-save %d+", "build-it-save 2"):gsub("\nxp [^\n]*", "")
	local back = assert(SaveCodec.decode(old, Config))
	assertEqual(nil, next(back.pools.villagers[1].xp))
end)

test("names round-trip; a format 3 save loads with names", function()
	local ctx = Session.new(World.new(20, 20), Config, 1)
	local v = Session.newVillager(1, 40, 40, Config)
	v.name = "Quin"
	table.insert(ctx.pools.villagers, v)
	ctx.pools.characters[1].name = "Zed"

	local text = SaveCodec.encode(ctx)
	local loaded = roundTrip(ctx)
	assertEqual("Quin", loaded.pools.villagers[1].name)
	assertEqual("Zed", loaded.pools.characters[1].name)

	local old = text:gsub("^build%-it%-save %d+", "build-it-save 3"):gsub(" name=s:%S+", "")
	local back = assert(SaveCodec.decode(old, Config))
	assertTrue(back.pools.villagers[1].name ~= nil)
	assertTrue(back.pools.characters[1].name ~= nil)
end)

test("needs round-trip for the player and villagers; a format 4 save loads with full needs", function()
	local ctx = Session.new(World.new(20, 20), Config, 1)
	local v = Session.newVillager(1, 40, 40, Config)
	v.name = "Quin"
	v.needs.health, v.needs.hunger, v.needs.tiredness = 0.4, 0.55, 0.25
	table.insert(ctx.pools.villagers, v)
	local p = ctx.pools.characters[1]
	p.needs.health, p.needs.hunger = 0.7, 0.3

	local text = SaveCodec.encode(ctx)
	local loaded = roundTrip(ctx)
	assertEqual(0.4, loaded.pools.villagers[1].needs.health)
	assertEqual(0.55, loaded.pools.villagers[1].needs.hunger)
	assertEqual(0.25, loaded.pools.villagers[1].needs.tiredness)
	assertEqual(0.7, loaded.pools.characters[1].needs.health)
	assertEqual(0.3, loaded.pools.characters[1].needs.hunger)

	local old = text:gsub("^build%-it%-save %d+", "build-it-save 4"):gsub(" health=n:%S+", ""):gsub(" hunger=n:%S+", ""):gsub(" tiredness=n:%S+", "")
	local back = assert(SaveCodec.decode(old, Config))
	assertEqual(1, back.pools.villagers[1].needs.health)
	assertEqual(0, back.pools.villagers[1].needs.hunger)
	assertEqual(1, back.pools.characters[1].needs.health)
end)

test("a refilling bush round-trips with its timer; format 5 saves still load", function()
	local world = World.new(20, 20)
	World.addNode(world, { id = 1, kind = "bush", tileX = 5, tileY = 5, variant = 2, stage = 3, amount = 0, refilling = 41.5 })
	local ctx = Session.new(world, Config, 1)

	local text = SaveCodec.encode(ctx)
	assertTrue(text:find("^build%-it%-save %d") ~= nil, "expected a format header")
	local n = roundTrip(ctx).pools.nodes[1]
	assertEqual("bush", n.kind)
	assertEqual(0, n.amount)
	assertEqual(41.5, n.refilling)

	local old = text:gsub("^build%-it%-save %d+", "build-it-save 5"):gsub(" refilling=n:%S+", "")
	local back = assert(SaveCodec.decode(old, Config))
	assertEqual(nil, back.pools.nodes[1].refilling)
end)

test("herds and deer round-trip, and a loaded herd keeps breeding; format 6 saves load with no deer", function()
	local AnimalSystem = require("src.game.systems.animal_system")
	local ctx = Session.new(World.new(40, 40), Config, 1)
	local herd = AnimalSystem.addHerd(ctx, 20, 20, 4)
	AnimalSystem.spawn(ctx, herd, 21, 20)
	AnimalSystem.spawn(ctx, herd, 19, 22)
	herd.breed = 12.5
	ctx.pools.animals[2].animator.facing = 3

	local text = SaveCodec.encode(ctx)
	assertTrue(text:find("^build%-it%-save 7") ~= nil, "expected format 7")
	local loaded = roundTrip(ctx)
	assertEqual(1, #loaded.pools.herds)
	local h = loaded.pools.herds[1]
	assertEqual(20, h.tileX)
	assertEqual(20, h.tileY)
	assertEqual(4, h.cap)
	assertEqual(12.5, h.breed)
	assertEqual(2, #loaded.pools.animals)
	local a = loaded.pools.animals[2]
	assertEqual(2, a.id)
	assertEqual(h.id, a.herd)
	assertEqual(ctx.pools.animals[2].x, a.x)
	assertEqual(ctx.pools.animals[2].y, a.y)
	assertEqual(3, a.animator.facing)
	assertEqual(3, ctx.nextAnimalId)
	assertEqual(3, loaded.nextAnimalId)
	run(loaded, Config.animals.deer.breedEvery)
	assertEqual(3, #loaded.pools.animals)

	local old = text:gsub("^build%-it%-save %d+", "build-it-save 6"):gsub("herd [^\n]*\n", ""):gsub("deer [^\n]*\n", "")
	local back = assert(SaveCodec.decode(old, Config))
	assertEqual(0, #back.pools.animals)
	assertEqual(0, #back.pools.herds)
end)
