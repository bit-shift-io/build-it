-- Hauling through the real app loop (docs/CONTEXT.md "Haul job"): a
-- woodcutter beside a forest and a sawmill a few tiles away. With no
-- player input at all, villagers carry the woodcutter's logs to the
-- sawmill's input, and the sawmill turns them into planks.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local Session = require("src.game.session")
local Placement = require("src.game.buildings.placement")
local StorageFacility = require("src.game.components.storage_facility")

local TILE = Config.tileSize

local function b(shape, x, y, w, d, extra)
	local r = { x = x, y = y, z = 0, width = w, depth = d, height = 1, shape = shape, rotation = 0, material = "plank", paint = 1 }
	for k, v in pairs(extra) do
		r[k] = v
	end
	return r
end

local WOODCUTTER = { id = "d1", name = "Woodcutter", versions = { { width = 2, depth = 1, bricks = {
	b("saw", 0, 0, 3, 1, { ability = "saw" }),
	b("output", 3, 3, 2, 1, { port = "output" }),
} } } }

local SAWMILL = { id = "d2", name = "Sawmill", versions = { { width = 2, depth = 1, bricks = {
	b("sawbench", 0, 0, 4, 2, { ability = "sawbench" }),
	b("input", 0, 3, 2, 1, { port = "input" }),
	b("output", 4, 3, 2, 1, { port = "output" }),
} } } }

local function port(building, kind)
	for _, p in ipairs(building.ports) do
		if p.kind == kind then
			return p
		end
	end
end

test("a woodcutter's logs reach a sawmill input with no player input", function()
	_G.love = LoveMock.new()
	local world = World.new(30, 30)
	local id = 0
	for y = 3, 5 do
		for x = 3, 6 do
			id = id + 1
			World.addNode(world, { id = id, kind = "tree", tileX = x, tileY = y, variant = 1, stage = 1, amount = Config.nodes.tree.amount })
		end
	end
	local game = GameHarness.startSession(world, { storage = Config.stockpile })
	local ctx = game.ctx
	Placement.build(ctx, { design = WOODCUTTER, version = 1, facing = "N", tileX = 4, tileY = 6 })
	local mill = Placement.build(ctx, { design = SAWMILL, version = 1, facing = "N", tileX = 14, tileY = 12 })
	for i = 1, 2 do
		table.insert(ctx.pools.villagers, Session.newVillager(i, (8 + i + 0.5) * TILE, 9.5 * TILE, Config))
	end

	local input, output = port(mill, "input"), port(mill, "output")
	local reached = false
	Fake.runUntil(game, function()
		reached = reached or (input.buffer.counts.log or 0) > 0
		return reached and (output.buffer.counts.plank or 0) > 0
	end, 60 * 60)
	assertTrue(reached, "logs reached the sawmill input")
	assertTrue((output.buffer.counts.plank or 0) > 0, "the sawmill made planks from them")
end)

test("haulers deliver to the starting storage facility standing on its input port tile", function()
	_G.love = LoveMock.new()
	local game = GameHarness.launch()
	Fake.tap(game, "return") -- New game
	local ctx = game.ctx
	local facility = ctx.pools.buildings[1]
	local input = port(facility, "input")
	local loaded = {}
	for i = 1, 3 do
		local v = ctx.pools.villagers[i]
		v.load.item, v.load.count = "log", 2
		loaded[i] = v
	end

	-- The tile each hauler stands on when its load empties.
	local droppedAt, dropped = {}, 0
	Fake.runUntil(game, function()
		for i, v in ipairs(loaded) do
			if not droppedAt[i] and v.load.count == 0 then
				droppedAt[i] = { x = math.floor(v.x / TILE), y = math.floor(v.y / TILE) }
				dropped = dropped + 1
			end
		end
		return dropped == #loaded
	end, 60 * 60)
	assertEqual(6, StorageFacility.totals(ctx).log)
	for i, t in ipairs(droppedAt) do
		assertEqual(input.x, t.x, "hauler " .. i)
		assertEqual(input.y, t.y, "hauler " .. i)
	end
end)

test("a hauler ends its trip and walks to the gather area, off the port tile", function()
	_G.love = LoveMock.new()
	local game = GameHarness.launch()
	Fake.tap(game, "return") -- New game
	local ctx = game.ctx
	local facility = ctx.pools.buildings[1]
	local v = ctx.pools.villagers[1]
	v.load.item, v.load.count = "log", 2
	local delivered = false
	Fake.runUntil(game, function()
		delivered = delivered or v.load.count == 0
		return delivered and v.job == nil and v.idle and v.idle.phase == "settled"
	end, 60 * 60)
	assertTrue(delivered, "the load was delivered")
	local x, y = math.floor(v.x / TILE), math.floor(v.y / TILE)
	assertTrue(World.isStandable(ctx.world, x, y), "settled on a standable tile")
	assertEqual(facility, v.idle.facility)
end)
