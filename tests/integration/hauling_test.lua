-- Hauling through the real app loop (docs/CONTEXT.md "Haul job"): a
-- woodcutter beside a forest and a sawmill a few tiles away. With no
-- player input at all, villagers carry the woodcutter's logs to the
-- sawmill's input, and the sawmill turns them into planks.
local GameHarness = require("tests.support.game_harness")
local FrameStepper = require("tests.support.frame_stepper")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local Session = require("src.game.session")
local Placement = require("src.game.buildings.placement")
local StorageFacility = require("src.game.components.storage_facility")

local TILE = Config.tileSize

local Designs = require("tests.support.designs")

-- A saw on a 2x1 tile floor with an output port on its south edge under
-- tile (1, 0).
local WOODCUTTER = Designs.floor(2, 1, Designs.ability("saw", 0.375, 0.125), Designs.port("output", 1, 1))

-- A saw bench on a 2x1 tile floor, an input port on its south edge under
-- tile (0, 0) and an output port under tile (1, 0).
local SAWMILL = Designs.floor(2, 1,
	Designs.ability("sawbench", 0.5, 0.25),
	Designs.port("input", 0.25, 1),
	Designs.port("output", 1.25, 1))

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
	Placement.build(ctx, Designs.request(WOODCUTTER, "N", 4, 6))
	local mill = Placement.build(ctx, Designs.request(SAWMILL, "N", 14, 12))
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

test("a building placed on settled villagers leaves them standing on standable tiles", function()
	_G.love = LoveMock.new()
	local game = GameHarness.startSession(World.new(30, 30), { storage = Config.stockpile })
	local ctx = game.ctx
	for i = 1, 4 do
		table.insert(ctx.pools.villagers, Session.newVillager(i, (12 + i + 0.5) * TILE, 17.5 * TILE, Config))
	end
	Fake.runUntil(game, function()
		for _, v in ipairs(ctx.pools.villagers) do
			if not (v.idle and v.idle.phase == "settled") then
				return false
			end
		end
		return true
	end, 60 * 30)

	-- The mill's footprint lands on the first villager's tile.
	local v1 = ctx.pools.villagers[1]
	local mill = Placement.build(ctx, Designs.request(SAWMILL, "N", math.floor(v1.x / TILE), math.floor(v1.y / TILE)))
	assertTrue(World.buildingAt(ctx.world, math.floor(v1.x / TILE), math.floor(v1.y / TILE)) == mill, "fixture: the villager is under the footprint")

	FrameStepper.step(game, FrameStepper.secondsToFrames(5))
	for i, v in ipairs(ctx.pools.villagers) do
		local x, y = math.floor(v.x / TILE), math.floor(v.y / TILE)
		assertTrue(World.isStandable(ctx.world, x, y), "villager " .. i .. " stands on " .. x .. "," .. y)
	end
end)
