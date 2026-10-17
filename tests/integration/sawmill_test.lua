-- A sawmill through the real input path: the player delivers logs on the
-- input port tile with E, and with no more player action a villager runs
-- the saw bench and haulers take the planks to the storage facility.
local GameHarness = require("tests.support.game_harness")
local FrameStepper = require("tests.support.frame_stepper")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local Inventory = require("src.game.components.inventory")
local DesignStore = require("src.app.design_store")
local Session = require("src.game.session")
local Storage = require("src.game.components.storage")
local Placement = require("src.game.buildings.placement")

local TILE = Config.tileSize

local function b(shape, x, y, w, d, extra)
	local r = { x = x, y = y, z = 0, width = w, depth = d, height = 1, shape = shape, rotation = 0, material = "plank", paint = 1 }
	for k, v in pairs(extra) do
		r[k] = v
	end
	return r
end

local SAWMILL = {
	id = "d1",
	name = "Sawmill",
	versions = { { width = 2, depth = 1, bricks = {
		b("sawbench", 0, 0, 4, 2, { ability = "sawbench" }),
		b("input", 0, 3, 2, 1, { port = "input" }),
		b("output", 4, 3, 2, 1, { port = "output" }),
	} } },
}

test("delivered logs become planks a villager makes and haulers store", function()
	_G.love = LoveMock.new()
	assert(DesignStore.write(Config.designs.dir, SAWMILL))
	local game = GameHarness.startSession(World.new(20, 20), { storage = Config.stockpile })
	local input, c = Fake.FakeInput.new(), game.ctx.pools.characters[1]
	Inventory.add(c.inventory, "log", 4)

	Fake.tap(game, "1")
	Fake.click(game, 1, 640 + (13 * TILE - c.x), 360 + (7.5 * TILE - c.y))
	GameHarness.completeSites(game)
	local facility, building = game.ctx.pools.buildings[1], game.ctx.pools.buildings[2]
	assert(building, "the sawmill was placed")
	local inPort = building.ports[1].kind == "input" and building.ports[1] or building.ports[2]

	Fake.holdFor(game, input, "w", 0.3)
	Fake.holdFor(game, input, "d", 0.5)
	assertEqual(inPort, World.portAt(game.ctx.world, math.floor(c.x / TILE), math.floor(c.y / TILE)))
	Fake.holdFor(game, input, "e", 1 / 60)
	assertEqual(4, inPort.buffer.counts.log, "logs delivered")

	local v = Session.newVillager(1, 5.5 * TILE, 12.5 * TILE, Config)
	table.insert(game.ctx.pools.villagers, v)
	for i = 2, 4 do
		table.insert(game.ctx.pools.villagers, Session.newVillager(i, (5 + i + 0.5) * TILE, 12.5 * TILE, Config))
	end
	local bench = building.functionBricks[1]
	local inside = false
	local planks = facility.storage.counts.plank or 0
	local trespass
	Fake.runUntil(game, function()
		for i, w in ipairs(game.ctx.pools.villagers) do
			if w.mover.enter == building and math.floor(w.x / TILE) == bench.tileX and math.floor(w.y / TILE) == bench.tileY then
				inside = true
			end
			local at = World.buildingAt(game.ctx.world, math.floor(w.x / TILE), math.floor(w.y / TILE))
			if at and w.mover.enter ~= at then
				trespass = trespass or string.format("villager %d stood on a footprint it may not enter", i)
			end
		end
		return (facility.storage.counts.plank or 0) >= planks + 2
	end, 60 * 120)
	assertTrue(World.buildingAt(game.ctx.world, bench.tileX, bench.tileY) == building, "the bench's tile is in the footprint")
	assertEqual(nil, trespass)
	assertTrue(inside, "the operator stood on the bench's tile")
	assertEqual(planks + 2, facility.storage.counts.plank, "both planks reached storage")
	assertEqual(nil, inPort.buffer.counts.log, "every log used")
end)

test("the saw bench operator never hauls and stays the same villager while others are free", function()
	_G.love = LoveMock.new()
	local game = GameHarness.startSession(World.new(20, 20), { storage = Config.stockpile })
	local ctx = game.ctx
	local facility = ctx.pools.buildings[1]
	local building = Placement.build(ctx, { design = SAWMILL, version = 1, facing = "N", tileX = 13, tileY = 7 })
	local inPort = building.ports[1].kind == "input" and building.ports[1] or building.ports[2]
	for _ = 1, 4 do
		Storage.add(inPort.buffer, "log")
	end
	for i = 1, 4 do
		table.insert(ctx.pools.villagers, Session.newVillager(i, (5 + i + 0.5) * TILE, 12.5 * TILE, Config))
	end

	FrameStepper.step(game, 1)
	local planks = facility.storage.counts.plank or 0
	local operators, hauledByOperator = {}, false
	local count = 0
	Fake.runUntil(game, function()
		for _, job in ipairs(ctx.pools.jobs) do
			if not job.dead and job.kind == "operate" then
				operators[job.villager] = true
			end
		end
		for _, job in ipairs(ctx.pools.jobs) do
			if not job.dead and job.kind == "haul" and operators[job.villager] then
				hauledByOperator = true
			end
		end
		count = 0
		for _ in pairs(operators) do
			count = count + 1
		end
		return (facility.storage.counts.plank or 0) >= planks + 2
	end, 60 * 240)
	assertEqual(planks + 2, facility.storage.counts.plank, "every plank reached storage")
	assertEqual(1, count, "one villager operated the bench across every cycle")
	assertFalse(hauledByOperator, "the operator held a haul job")
end)

test("the log route from storage to the saw bench is served by one villager across trips", function()
	_G.love = LoveMock.new()
	local game = GameHarness.startSession(World.new(20, 20), { storage = {} })
	local ctx = game.ctx
	local facility = ctx.pools.buildings[1]
	local building = Placement.build(ctx, { design = SAWMILL, version = 1, facing = "N", tileX = 13, tileY = 7 })
	for i = 1, 4 do
		table.insert(ctx.pools.villagers, Session.newVillager(i, (5 + i + 0.5) * TILE, 12.5 * TILE, Config))
	end

	-- One log at a time, so each trip is its own job; a new log appears once
	-- the last trip has ended.
	local haulers, trips, current = {}, 0, nil
	Storage.add(facility.storage, "log")
	Fake.runUntil(game, function()
		if current and current.dead then
			current = nil
			Storage.add(facility.storage, "log")
		end
		for _, job in ipairs(ctx.pools.jobs) do
			if not current and not job.dead and job.kind == "haul" and job.item == "log" and job.dest.building == building then
				current = job
				trips = trips + 1
				haulers[job.villager] = true
			end
		end
		return trips >= 3 and current == nil
	end, 60 * 240)
	local count = 0
	for _ in pairs(haulers) do
		count = count + 1
	end
	assertTrue(trips >= 3, "several log trips")
	assertEqual(1, count, "one villager hauled every log trip")
end)
