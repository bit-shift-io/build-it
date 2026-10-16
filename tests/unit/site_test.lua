-- Construction sites (docs/CONTEXT.md "Construction site", "Build job"):
-- placing a design reserves its cost in storage and leaves a site; haul
-- jobs carry the cost to it, a build job turns it into a building.
local Config = require("src.game.config")
local Session = require("src.game.session")
local World = require("src.game.world")
local Storage = require("src.game.components.storage")
local StorageFacility = require("src.game.components.storage_facility")
local Placement = require("src.game.buildings.placement")
local Cost = require("src.game.builder.cost")
local Site = require("src.game.buildings.site")

local TILE = Config.tileSize

local function brick(x, y, extra)
	local t = { x = x, y = y, z = 0, width = 1, depth = 1, shape = "1x1", rotation = 0, material = "plank", paint = 1 }
	for k, v in pairs(extra or {}) do
		t[k] = v
	end
	return t
end

-- A 2x1 hall with an output port on its south edge under tile (1, 0).
local HALL = {
	id = "d1",
	name = "Hall",
	versions = { { width = 2, depth = 1, bricks = { brick(0, 0), brick(6, 3, { port = "output" }) } } },
}
local COST = Cost.of(HALL.versions[1], Config)

-- A 1x1-tile storage facility: a depot and storage bricks, no ports.
local STORE = {
	id = "d9",
	name = "Store",
	versions = {
		{
			width = 1,
			depth = 1,
			bricks = {
				{ x = 0, y = 0, z = 0, width = 2, depth = 2, shape = "depot", rotation = 0, material = "plank", paint = 1, ability = "depot" },
				{ x = 2, y = 0, z = 0, width = 2, depth = 2, shape = "storage", rotation = 0, material = "plank", paint = 1, storage = 8 },
			},
		},
	},
}

local function facility(ctx, x, y, items)
	local f = Placement.build(ctx, { design = STORE, version = 1, facing = "N", tileX = x, tileY = y })
	f.storage.capacity = 1000
	for item, n in pairs(items) do
		for _ = 1, n do
			Storage.add(f.storage, item)
		end
	end
	return f
end

local function request(x, y)
	return { design = HALL, version = 1, facing = "N", tileX = x, tileY = y }
end

local function newSession(planks)
	local ctx = Session.new(World.new(20, 20), Config, 1)
	local f = facility(ctx, 10, 10, { plank = planks or COST.plank })
	return ctx, f
end

test("placing leaves a site, not a building, and reserves its cost in storage", function()
	local ctx, f = newSession(COST.plank + 3)

	local site = assert(Placement.place(ctx, request(4, 4)))

	assertEqual(1, #ctx.pools.buildings, "only the facility")
	assertEqual(site, ctx.pools.sites[1])
	assertEqual(COST.plank + 3, f.storage.counts.plank, "the stock stays in storage until hauled")
	assertEqual(3, StorageFacility.totals(ctx).plank, "reserved stock is not available")
	assertEqual(3, Storage.available(f.storage, "plank"))
end)

test("a second placement that needs more than the unclaimed stock is unaffordable", function()
	local ctx = newSession(COST.plank * 2 - 1)
	assert(Placement.place(ctx, request(4, 4)))

	local site, reason = Placement.place(ctx, request(4, 7))

	assertEqual(nil, site)
	assertEqual("unaffordable", reason)
	assertEqual(1, #ctx.pools.sites)
end)

test("a site blocks its footprint for placement and the player, not villagers", function()
	local ctx = newSession(COST.plank * 2)
	local site = assert(Placement.place(ctx, request(4, 4)))

	assertEqual(site, World.buildingAt(ctx.world, 5, 4))
	assertTrue(World.isBlocked(ctx.world, 4, 4))
	assertFalse(World.isBlocked(ctx.world, 4, 4, true))
	assertEqual(nil, World.portAt(ctx.world, 5, 5), "its port tile stays open ground")
	local _, reason = Placement.check(ctx, request(5, 4))
	assertEqual("building", reason)
end)

local function addVillager(ctx, x, y)
	local v = Session.newVillager(#ctx.pools.villagers + 1, (x + 0.5) * TILE, (y + 0.5) * TILE, Config)
	table.insert(ctx.pools.villagers, v)
	return v
end

local function stepUntil(ctx, done, frames)
	for _ = 1, frames do
		Session.advance(ctx, 1 / 60)
		if done() then
			return true
		end
	end
	return false
end

local function jobOf(ctx, kind)
	for _, job in ipairs(ctx.pools.jobs) do
		if job.kind == kind and not job.dead then
			return job
		end
	end
end

test("villagers haul the claimed cost from storage to the site", function()
	local ctx, f = newSession(COST.plank + 3)
	local site = assert(Placement.place(ctx, request(4, 4)))
	addVillager(ctx, 8, 8)

	Session.advance(ctx, 1 / 60)
	local haul = jobOf(ctx, "haul")
	assert(haul, "a haul job to the site")
	assertEqual(site, haul.dest.building)
	assertEqual(f, haul.source.building)

	assertTrue(stepUntil(ctx, function()
		return (site.delivered.counts.plank or 0) == COST.plank
	end, 60 * 120), "everything delivered")
	assertEqual(3, f.storage.counts.plank, "only the cost left storage")
	assertEqual(nil, f.storage.claimed and f.storage.claimed.plank, "no claim left")
	assertEqual(3, StorageFacility.totals(ctx).plank)
end)

test("a build job starts only once everything is delivered, then the site becomes a building", function()
	local ctx = newSession(COST.plank)
	local site = assert(Placement.place(ctx, request(4, 4)))
	addVillager(ctx, 8, 8)
	addVillager(ctx, 9, 8)

	local early = false
	assertTrue(stepUntil(ctx, function()
		local build = jobOf(ctx, "build")
		if build and not Site.supplied(site) then
			early = true
		end
		return build ~= nil
	end, 60 * 120), "a build job")
	assertFalse(early, "no build job before all materials arrived")
	local build = jobOf(ctx, "build")
	assertEqual(site, build.site)

	local built = Site.buildTime(site, Config)
	assertEqual(Config.villagers.buildTime * 2, built, "scaled by the footprint")
	assertTrue(stepUntil(ctx, function()
		return #ctx.pools.buildings == 2
	end, math.ceil(built * 60) + 60 * 10), "the site turned into a building")

	assertEqual(0, #ctx.pools.sites)
	local b = ctx.pools.buildings[2]
	assertEqual(HALL, b.design)
	assertEqual(4, b.tileX)
	assertEqual(4, b.tileY)
	assertEqual(b, World.buildingAt(ctx.world, 4, 4))
	assertEqual(b.ports[1], World.portAt(ctx.world, 5, 5))
	assertEqual(nil, next(b.ports[1].buffer.counts), "empty buffers")
	assertEqual(nil, next(b.storage.counts))
	for _, v in ipairs(ctx.pools.villagers) do
		assertEqual(nil, v.job, "the builder is free again")
	end
end)

local Ports = require("src.game.components.ports")
local Inventory = require("src.game.components.inventory")

-- A 1x1 depot with an input port on its north edge and an output port on
-- its east edge, and no storage bricks.
local PORTED = {
	id = "d8",
	name = "Ported store",
	versions = {
		{
			width = 1,
			depth = 1,
			bricks = {
				{ x = 0, y = 0, z = 0, width = 2, depth = 2, shape = "depot", rotation = 0, material = "plank", paint = 1, ability = "depot" },
				{ x = 0, y = 3, z = 0, width = 2, depth = 1, shape = "input", rotation = 0, material = "plank", paint = 1, port = "input" },
				{ x = 3, y = 0, z = 0, width = 1, depth = 2, shape = "output", rotation = 0, material = "plank", paint = 1, port = "output" },
			},
		},
	},
}

local function portOf(b, kind)
	for _, port in ipairs(b.ports) do
		if port.kind == kind then
			return port
		end
	end
end

test("claimed items in a depot's buffers stay there: not stored, not collected", function()
	local ctx = Session.new(World.new(20, 20), Config, 1)
	local f = Placement.build(ctx, { design = PORTED, version = 1, facing = "N", tileX = 10, tileY = 10 })
	local input, output = portOf(f, "input"), portOf(f, "output")
	f.storage.capacity, input.buffer.capacity, output.buffer.capacity = 1000, 1000, 1000
	for _ = 1, COST.plank - 1 do
		Storage.add(input.buffer, "plank")
	end
	Storage.add(output.buffer, "plank")
	assert(Placement.place(ctx, request(4, 4)))

	Session.advance(ctx, 1 / 60)
	local inv = Inventory.new()
	Ports.collect(output, inv)

	assertEqual(COST.plank - 1, input.buffer.counts.plank, "the claimed input stays for its haul")
	assertEqual(0, Inventory.count(inv, "plank"), "the player can't take claimed stock")
	assertEqual(1, output.buffer.counts.plank)
end)
