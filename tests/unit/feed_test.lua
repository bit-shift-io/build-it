-- Feed jobs (src/game/jobs/feed.lua, docs/CONTEXT.md "Feed job", "Collapse"):
-- a free villager carries food from the nearest store to a collapsed
-- villager, who eats it on delivery and gets up.
local Session = require("src.game.session")
local World = require("src.game.world")
local Config = require("src.game.config")
local Placement = require("src.game.buildings.placement")
local Storage = require("src.game.components.storage")
local Status = require("src.game.components.status")

local TILE = Config.tileSize
local STEP = 1 / 60

local function brick(shape, x, y, extra)
	local b = { x = x, y = y, z = 0, width = 2, depth = 1, height = 1, shape = shape, rotation = 0, material = "plank", paint = 1 }
	for k, v in pairs(extra or {}) do
		b[k] = v
	end
	return b
end

local STORE = { id = "d5", name = "Store", versions = { { width = 1, depth = 1, bricks = {
	brick("depot", 0, 0, { ability = "depot" }),
	brick("storage", 2, 0, { storage = 8 }),
	brick("input", 0, 3, { port = "input" }),
	brick("output", 2, 3, { port = "output" }),
} } } }

local function place(ctx, x, y)
	return Placement.build(ctx, { design = STORE, version = 1, facing = "N", tileX = x, tileY = y })
end

local function villager(ctx, tileX, tileY, name)
	local v = Session.newVillager(#ctx.pools.villagers + 1, (tileX + 0.5) * TILE, (tileY + 0.5) * TILE, Config)
	v.name = name
	table.insert(ctx.pools.villagers, v)
	return v
end

local function collapse(v)
	v.needs.hunger = 1
	v.needs.health = 0
end

local function feeders(ctx)
	local n = 0
	for _, job in ipairs(ctx.pools.jobs) do
		if job.kind == "feed" and not job.dead then
			n = n + 1
		end
	end
	return n
end

local function newCtx()
	return Session.new(World.new(30, 30), Config, 1)
end

test("a collapsed villager and stored food produce one feed job, and delivery revives it", function()
	local ctx = newCtx()
	local store = place(ctx, 4, 2)
	for _ = 1, 4 do
		Storage.add(store.storage, "meat")
	end
	local sick = villager(ctx, 10, 8, "Ada")
	local helper = villager(ctx, 6, 8, "Bo")
	collapse(sick)

	Session.advance(ctx, STEP)
	assertEqual(1, feeders(ctx))
	assertEqual("feed", helper.job and helper.job.kind)
	assertEqual("Feeding Ada", Status.activity(helper))
	assertEqual(nil, sick.job)

	for _ = 1, 60 * 60 do
		Session.advance(ctx, STEP)
		if sick.needs.health > 0 then
			break
		end
	end
	assertTrue(sick.needs.health > 0, "health rose above 0")
	assertTrue(sick.needs.hunger < Config.needs.starvingAt, "ate a meal")
	assertEqual(nil, helper.job)
	assertEqual(0, feeders(ctx))
end)

test("only one feeder goes per collapsed villager", function()
	local ctx = newCtx()
	local store = place(ctx, 4, 2)
	for _ = 1, 6 do
		Storage.add(store.storage, "meat")
	end
	local sick = villager(ctx, 10, 8, "Ada")
	villager(ctx, 6, 8, "Bo")
	villager(ctx, 7, 8, "Cy")
	collapse(sick)

	for _ = 1, 120 do
		Session.advance(ctx, STEP)
		assertTrue(feeders(ctx) <= 1, "never two feeders")
	end
end)

test("with no food anywhere there is no feed job and nobody is stuck", function()
	local ctx = newCtx()
	place(ctx, 4, 2)
	local sick = villager(ctx, 10, 8, "Ada")
	local helper = villager(ctx, 6, 8, "Bo")
	collapse(sick)

	for _ = 1, 120 do
		Session.advance(ctx, STEP)
	end
	assertEqual(0, #ctx.pools.jobs)
	assertEqual(nil, helper.job)
	assertEqual(nil, sick.feeder)
end)

test("a feeder that collapses on the way puts the food back and frees the target", function()
	local ctx = newCtx()
	local store = place(ctx, 4, 2)
	for _ = 1, 4 do
		Storage.add(store.storage, "meat")
	end
	local sick = villager(ctx, 10, 8, "Ada")
	local helper = villager(ctx, 6, 8, "Bo")
	collapse(sick)

	Session.advance(ctx, STEP)
	assertEqual("feed", helper.job and helper.job.kind)
	collapse(helper)
	Session.advance(ctx, STEP)
	assertEqual(nil, helper.job)
	assertEqual(nil, sick.feeder)
	local held = (store.storage.counts.meat or 0)
	for _, port in ipairs(store.ports) do
		held = held + (port.buffer.counts.meat or 0)
	end
	assertEqual(4, held)
end)
