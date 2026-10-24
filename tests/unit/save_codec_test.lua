-- The world save codec (src/game/save/codec.lua): a session turns into the
-- text of the save file and back, and a loaded session steps exactly like
-- the one it was saved from.
local Session = require("src.game.session")
local Builtins = require("tests.support.builtins")
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

local Designs = require("tests.support.designs")
local Blueprint = require("src.game.buildings.blueprint")

-- A 2x1 tile works: a saw, a saw bench, storage, and an input and an output
-- port on the south edge.
local WORKS = Designs.floor(2, 1,
	Designs.ability("saw", 0.5, 0.25),
	Designs.ability("sawbench", 1.5, 0.25),
	Designs.storage(8, 0.25, 0.625),
	Designs.port("input", 0.25, 1),
	Designs.port("output", 1.25, 1))

-- A session with a working, part-filled works facing E beside a few trees.
local function busySession()
	local world = World.new(30, 30)
	for i = 1, 4 do
		World.addNode(world, { id = i, kind = "tree", tileX = 8 + i, tileY = 8, variant = i, stage = 1, amount = Config.nodes.tree.amount })
	end
	local ctx = Session.new(world, Config, 3)
	local c = ctx.pools.characters[1]
	c.inventory = Inventory.new({ plank = 10000, stone = 10000, log = 5 })
	local b = assert(Placement.build(ctx, Designs.request(WORKS, "E", 10, 10, "Works")))
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
	for _, key in ipairs({ "id", "design", "facing", "tileX", "tileY", "width", "depth", "full" }) do
		assertEqual(b[key], lb[key], key)
	end
	assertEqual("Works", lb.design)
	assertEqual(b.blueprint.hash, lb.blueprint.hash)
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

local FORESTER = Designs.floor(2, 1, Designs.ability("planter", 0.5, 0.25))

test("a loaded session steps exactly like the session it was saved from", function()
	local ctx = busySession()
	local c = ctx.pools.characters[1]
	assert(Placement.build(ctx, Designs.request(FORESTER, "N", 20, 20, "Forester")))
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

-- Every field of `a` equals `b`'s, tables compared field by field.
local function assertSame(a, b, path)
	assertEqual(type(a), type(b), path)
	if type(a) ~= "table" then
		assertEqual(a, b, path)
		return
	end
	for k, v in pairs(a) do
		assertSame(v, b[k], path .. "." .. tostring(k))
	end
	for k in pairs(b) do
		assertTrue(a[k] ~= nil, path .. "." .. tostring(k) .. " is extra")
	end
end

test("a building's blueprint round-trips whole from the save itself, mesh and all", function()
	local ctx, b = busySession()
	local loaded = roundTrip(ctx)
	local lb = loaded.pools.buildings[1]
	assertSame(b.blueprint, lb.blueprint, "blueprint")
	assertEqual(Blueprint.hash(lb.blueprint), lb.blueprint.hash, "its hash is its content's")
end)

test("a textured building's blueprint round-trips with each vertex's texture", function()
	local ctx = busySession()
	local shed = 'return group{ box{ size = { 1, 1, 0.5 }, material = { name = "plank", variant = "bark", scale = 2, rotation = 90 } } }'
	local b = assert(Placement.build(ctx, Designs.request(shed, "N", 20, 20, "Shed")))
	assertTrue(b.blueprint.mesh[1].texture ~= nil, "expected a textured mesh")
	local lb = roundTrip(ctx).pools.buildings[2].blueprint
	assertSame(b.blueprint, lb, "blueprint")
	assertEqual(b.blueprint.hash, lb.hash)
end)

test("a building's walk grid round-trips with its blueprint", function()
	local ctx, b = busySession()
	local walk = roundTrip(ctx).pools.buildings[1].blueprint.walk
	assertEqual(b.blueprint.walk.width, walk.width)
	assertEqual(b.blueprint.walk.depth, walk.depth)
	assertEqual(b.blueprint.walk.cells, walk.cells)
end)

test("buildings and sites placed from one blueprint share one saved blueprint", function()
	local ctx, b = busySession()
	local twin = assert(Placement.build(ctx, Designs.request(WORKS, "N", 20, 20, "Works")))
	local text = SaveCodec.encode(ctx)
	local _, count = text:gsub("\nblueprint ", "")
	assertEqual(1, count)
	local loaded = roundTrip(ctx)
	assertTrue(loaded.pools.buildings[1].blueprint == loaded.pools.buildings[2].blueprint, "one table")
	assertEqual(twin.blueprint.hash, loaded.pools.buildings[2].blueprint.hash)
	assertEqual(b.blueprint.hash, loaded.pools.buildings[1].blueprint.hash)
end)

test("text that is not a readable save is refused with a reason", function()
	local ctx = busySession()
	local good = SaveCodec.encode(ctx)
	for _, text in ipairs({
		"",
		"build-it-design 1\n",
		good:gsub("blueprint=n:1", "blueprint=n:9"),
		good:gsub("\nworld [^\n]*", ""),
		good .. "mystery a=n:1\n",
	}) do
		local loaded, reason = SaveCodec.decode(text, Config)
		assertEqual(nil, loaded)
		assertEqual("string", type(reason))
	end
end)

test("a save from before walk grids (format 8 and older) is refused as too old", function()
	local text = SaveCodec.encode(Session.new(World.new(20, 20), Config, 1))
	for _, format in ipairs({ 1, 7, 8 }) do
		local old = text:gsub("^build%-it%-save %d+", "build-it-save " .. format)
		local loaded, reason = SaveCodec.decode(old, Config)
		assertEqual(nil, loaded)
		assertEqual("save is from an older version of the game (format " .. format .. ")", reason)
	end
end)

local Starter = require("src.game.designs.starter")
local WorldGen = require("src.game.world_gen")

test("a new game round-trips: the starter facility, its blueprint and its stored stockpile", function()
	local ctx = Session.newGame(WorldGen.generate(Config, 1), Config, 1, Builtins)
	run(ctx, 0.5)

	local loaded = roundTrip(ctx)
	local b, lb = ctx.pools.buildings[1], loaded.pools.buildings[1]
	assertEqual(Starter.NAME, lb.design)
	assertEqual(b.blueprint.hash, lb.blueprint.hash)
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
	local ctx = Session.newGame(WorldGen.generate(Config, 1), Config, 1, Builtins)
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

test("a walk saved mid-way keeps which waypoints are stud cells inside a building", function()
	local ctx = Session.newGame(WorldGen.generate(Config, 1), Config, 1, Builtins)
	local v = ctx.pools.villagers[2]
	local b = ctx.pools.buildings[1]
	assertTrue(Walker.goInside(v, ctx, b, b.tileX + b.width / 2, b.tileY + b.depth / 2))
	run(ctx, 0.3)
	local studs = 0
	for _, p in ipairs(v.walker.path) do
		studs = studs + (p.stud and 1 or 0)
	end
	assertTrue(studs > 0, "fixture: stud waypoints still ahead when saved")

	local lv = roundTrip(ctx).pools.villagers[2]
	assertEqual(#v.walker.path, #lv.walker.path)
	for k, p in ipairs(v.walker.path) do
		assertEqual(p.x, lv.walker.path[k].x)
		assertEqual(p.y, lv.walker.path[k].y)
		assertEqual(p.stud, lv.walker.path[k].stud)
	end
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

-- A 1x1 cutter: a saw and an output port on its south edge.
local CUTTER = Designs.floor(1, 1, Designs.ability("saw", 0.25, 0.25), Designs.port("output", 0.25, 1))
-- A 1x1 store: a depot, storage for 8 and an input port on its south edge.
local STORE = Designs.floor(1, 1, Designs.ability("depot", 0.25, 0.25), Designs.storage(8, 0.75, 0.25), Designs.port("input", 0.25, 1))

test("saving and loading mid-haul loses no items; the hauler takes its load to storage", function()
	local ctx = Session.new(World.new(30, 30), Config, 1)
	local cutter = assert(Placement.build(ctx, Designs.request(CUTTER, "N", 3, 3, "Cutter")))
	local store = assert(Placement.build(ctx, Designs.request(STORE, "N", 20, 3, "Store")))
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
	local mill = assert(Placement.build(ctx, Designs.request(Designs.floor(2, 1,
		Designs.ability("sawbench", 0.5, 0.25),
		Designs.port("input", 0.25, 1),
		Designs.port("output", 1.25, 1)), "N", 5, 5, "Mill")))
	assert(Placement.build(ctx, Designs.request(STORE, "N", 20, 5, "Store")))
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
	local b = assert(Placement.build(ctx, Designs.request(Designs.floor(2, 1,
		Designs.ability("saw", 0.375, 0.125),
		Designs.port("output", 1.25, 1)), "N", 10, 10, "Cutter")))
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

-- A 6x4 hall (costing several planks): no function role, an output port on its south edge.
local HALL = Designs.floor(6, 4, Designs.port("output", 1.625, 4))

local function siteSession()
	local ctx = Session.new(World.new(30, 30), Config, 1)
	local store = assert(Placement.build(ctx, Designs.request(Designs.floor(1, 1,
		Designs.ability("depot", 0.25, 0.25),
		Designs.storage(8, 0.75, 0.25),
		Designs.port("input", 0.25, 1),
		Designs.port("output", 0.75, 1)), "N", 20, 3, "Store")))
	store.storage.capacity = 1000
	local cost = Designs.blueprint(HALL).cost.plank
	for _ = 1, cost + 5 do
		Storage.add(store.storage, "plank")
	end
	local site = assert(Placement.place(ctx, Designs.request(HALL, "N", 5, 5, "Hall")))
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
	assertEqual("Hall", ls.design)
	assertEqual(site.blueprint.hash, ls.blueprint.hash)
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

test("villager experience round-trips", function()
	local ctx = Session.new(World.new(20, 20), Config, 1)
	local v = Session.newVillager(1, 40, 40, Config)
	v.xp.haul, v.xp.saw = 3, 25
	table.insert(ctx.pools.villagers, v)
	table.insert(ctx.pools.villagers, Session.newVillager(2, 60, 60, Config))

	local loaded = roundTrip(ctx)
	assertEqual(3, loaded.pools.villagers[1].xp.haul)
	assertEqual(25, loaded.pools.villagers[1].xp.saw)
	assertEqual(nil, next(loaded.pools.villagers[2].xp))
end)

test("names round-trip", function()
	local ctx = Session.new(World.new(20, 20), Config, 1)
	local v = Session.newVillager(1, 40, 40, Config)
	v.name = "Quin"
	table.insert(ctx.pools.villagers, v)
	ctx.pools.characters[1].name = "Zed"

	local loaded = roundTrip(ctx)
	assertEqual("Quin", loaded.pools.villagers[1].name)
	assertEqual("Zed", loaded.pools.characters[1].name)
end)

test("needs round-trip for the player and villagers", function()
	local ctx = Session.new(World.new(20, 20), Config, 1)
	local v = Session.newVillager(1, 40, 40, Config)
	v.name = "Quin"
	v.needs.health, v.needs.hunger, v.needs.tiredness = 0.4, 0.55, 0.25
	table.insert(ctx.pools.villagers, v)
	local p = ctx.pools.characters[1]
	p.needs.health, p.needs.hunger = 0.7, 0.3

	local loaded = roundTrip(ctx)
	assertEqual(0.4, loaded.pools.villagers[1].needs.health)
	assertEqual(0.55, loaded.pools.villagers[1].needs.hunger)
	assertEqual(0.25, loaded.pools.villagers[1].needs.tiredness)
	assertEqual(0.7, loaded.pools.characters[1].needs.health)
	assertEqual(0.3, loaded.pools.characters[1].needs.hunger)
end)

test("a refilling bush round-trips with its timer", function()
	local world = World.new(20, 20)
	World.addNode(world, { id = 1, kind = "bush", tileX = 5, tileY = 5, variant = 2, stage = 3, amount = 0, refilling = 41.5 })
	local ctx = Session.new(world, Config, 1)

	local text = SaveCodec.encode(ctx)
	assertTrue(text:find("^build%-it%-save %d") ~= nil, "expected a format header")
	local n = roundTrip(ctx).pools.nodes[1]
	assertEqual("bush", n.kind)
	assertEqual(0, n.amount)
	assertEqual(41.5, n.refilling)
end)

test("herds and deer round-trip, and a loaded herd keeps breeding", function()
	local AnimalSystem = require("src.game.systems.animal_system")
	local ctx = Session.new(World.new(40, 40), Config, 1)
	local herd = AnimalSystem.addHerd(ctx, 20, 20, 4)
	AnimalSystem.spawn(ctx, herd, 21, 20)
	AnimalSystem.spawn(ctx, herd, 19, 22)
	herd.breed = 12.5
	ctx.pools.animals[2].animator.facing = 3

	local text = SaveCodec.encode(ctx)
	assertTrue(text:find("^build%-it%-save 9") ~= nil, "expected format 9")
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
end)
