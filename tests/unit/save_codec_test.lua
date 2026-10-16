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
	local b = assert(Placement.place(ctx, c, { design = works(), version = 1, facing = "E", tileX = 10, tileY = 10 }))
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
	assertTrue(b.functionBricks[1].node ~= nil, "fixture: expected the saw to hold a node")

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
		assertEqual(fb.converting, lfb.converting)
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
	assert(Placement.place(ctx, c, { design = forester(), version = 1, facing = "N", tileX = 20, tileY = 20 }))
	-- Stand beside tree 4 (tile 12, 8) and hand-harvest it.
	c.x, c.y = 12.5 * Config.tileSize, 9.2 * Config.tileSize
	ctx.intents[1] = { x = 0, y = 0, harvest = true }
	run(ctx, 1.3)
	assertTrue(c.harvester.node ~= nil and c.harvester.progress > 0, "fixture: expected a hand harvest under way")

	local loaded = roundTrip(ctx)
	for _, session in ipairs({ ctx, loaded }) do
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
