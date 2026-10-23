-- Meals and the eat job (src/game/jobs/eat.lua, docs/CONTEXT.md "Meal",
-- "Feed job"): a meal eats one item at a time, highest fill first, until
-- hunger reaches 0; a hungry villager walks to the nearest storage
-- facility output port holding food, reserving what it will eat.
local Session = require("src.game.session")
local World = require("src.game.world")
local Config = require("src.game.config")
local Placement = require("src.game.buildings.placement")
local Storage = require("src.game.components.storage")
local Eat = require("src.game.jobs.eat")

local TILE = Config.tileSize
local STEP = 1 / 60

local Designs = require("tests.support.designs")

-- A storage facility with an input and an output port on its south edge.
local STORE = Designs.floor(1, 1,
	Designs.ability("depot", 0.25, 0.125),
	Designs.storage(8, 0.75, 0.125),
	Designs.port("input", 0.25, 1),
	Designs.port("output", 0.75, 1))

local function place(ctx, x, y)
	return Placement.build(ctx, Designs.request(STORE, "N", x, y))
end

local CANTEEN = Designs.floor(1, 1, Designs.ability("canteen", 0.25, 0.125), Designs.port("input", 0.25, 1))

local function villager(ctx, tileX, tileY)
	local v = Session.newVillager(#ctx.pools.villagers + 1, (tileX + 0.5) * TILE, (tileY + 0.5) * TILE, Config)
	table.insert(ctx.pools.villagers, v)
	return v
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

-- Every berry a facility holds, in its storage and its output buffers (a
-- facility's storage drains into its output buffers), and how many are
-- reserved.
local function berries(b)
	local held, reserved = b.storage.counts.berry or 0, b.storage.reserved and b.storage.reserved.berry or 0
	for _, port in ipairs(b.ports) do
		held = held + (port.buffer.counts.berry or 0)
		reserved = reserved + (port.buffer.reserved and port.buffer.reserved.berry or 0)
	end
	return held, reserved
end

local function newCtx()
	return Session.new(World.new(30, 30), Config, 1)
end

test("a meal picks the highest fill first and stops once hunger would reach 0", function()
	local have = { berry = 5, meat = 5, fish = 5 }
	local plan = Eat.plan(function(item) return have[item] or 0 end, 0.6, Config.food)
	assertEqual(2, #plan)
	assertEqual("meat", plan[1])
	assertEqual("meat", plan[2])
end)

test("a meal eats every food there is when it is not enough", function()
	local have = { berry = 1, fish = 1 }
	local plan = Eat.plan(function(item) return have[item] or 0 end, 1, Config.food)
	assertEqual("fish", plan[1])
	assertEqual("berry", plan[2])
	assertEqual(2, #plan)
end)

test("a meal is empty with no hunger or no food", function()
	assertEqual(0, #Eat.plan(function() return 9 end, 0, Config.food))
	assertEqual(0, #Eat.plan(function() return 0 end, 0.9, Config.food))
end)

test("a hungry villager walks to storage, eats a meal and is free again", function()
	local ctx = newCtx()
	local store = place(ctx, 4, 2)
	fill(store.ports[2].buffer, "berry", 4)
	local v = villager(ctx, 6, 8)
	v.needs.hunger = Config.needs.hungryAt

	run(ctx, 0.1)
	assertEqual("eat", v.job and v.job.kind)
	local _, reserved = berries(store)
	assertEqual(3, reserved, "reserves the meal")

	for _ = 1, 30 * 60 do
		Session.advance(ctx, STEP)
		if not v.job then
			break
		end
	end
	assertEqual(nil, v.job)
	local held, left = berries(store)
	assertEqual(1, held)
	assertEqual(0, left)
	assertTrue(v.needs.hunger < Config.needs.hungryAt, "no longer hungry")
	assertTrue(v.needs.hunger < 0.05, "ate until hunger reached 0")
end)

test("two hungry villagers never chase the last berry", function()
	local ctx = newCtx()
	local store = place(ctx, 4, 2)
	fill(store.storage, "berry", 1)
	local a, b = villager(ctx, 6, 8), villager(ctx, 7, 8)
	a.needs.hunger, b.needs.hunger = 0.6, 0.6

	run(ctx, 0.1)
	local eaters = 0
	for _, v in ipairs({ a, b }) do
		if v.job and v.job.kind == "eat" then
			eaters = eaters + 1
		end
	end
	assertEqual(1, eaters)
	local _, reserved = berries(store)
	assertEqual(1, reserved)
end)

test("a hungry villager with no food anywhere takes no job and idles", function()
	local ctx = newCtx()
	place(ctx, 4, 2)
	local v = villager(ctx, 6, 8)
	v.needs.hunger = 0.7

	run(ctx, 2)
	assertEqual(nil, v.job)
	assertEqual(0, #ctx.pools.jobs)
	assertTrue(v.idle ~= nil, "idles around the facility")
end)

test("the nearest facility holding food is the one eaten from", function()
	local ctx = newCtx()
	local far = place(ctx, 20, 2)
	local near = place(ctx, 4, 2)
	local empty = place(ctx, 8, 2)
	fill(far.storage, "berry", 5)
	fill(near.storage, "berry", 5)
	local v = villager(ctx, 7, 8)
	v.needs.hunger = 0.7

	run(ctx, 30)
	assertEqual(5, berries(far))
	assertTrue(berries(near) < 5, "ate at the near one")
end)

test("a hungry villager eats at a nearer stocked canteen, not at storage", function()
	local ctx = newCtx()
	local store = place(ctx, 4, 2)
	fill(store.storage, "berry", 5)
	local canteen = Placement.build(ctx, Designs.request(CANTEEN, "N", 20, 2))
	local buffer = canteen.ports[1].buffer
	fill(buffer, "berry", Storage.room(buffer))
	local full = buffer.counts.berry
	local v = villager(ctx, 21, 8)
	v.needs.hunger = 0.7

	for _ = 1, 60 * 30 do
		Session.advance(ctx, STEP)
		if v.needs.hunger < 0.7 then
			break
		end
	end
	assertTrue(v.needs.hunger < 0.7, "hunger dropped")
	assertEqual(5, berries(store), "storage untouched")
	assertTrue(buffer.counts.berry < full, "ate at the canteen")
end)
