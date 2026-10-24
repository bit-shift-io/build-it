-- Construction sites (docs/CONTEXT.md "Construction site", "Build job"):
-- placing a design reserves its cost in storage and leaves a site; haul
-- jobs carry the cost to it, a build job turns it into a building.
local Config = require("src.game.config")
local Session = require("src.game.session")
local World = require("src.game.world")
local Storage = require("src.game.components.storage")
local StorageFacility = require("src.game.components.storage_facility")
local Placement = require("src.game.buildings.placement")
local Designs = require("tests.support.designs")
local Site = require("src.game.buildings.site")

local TILE = Config.tileSize

-- A 2x1 hall with an output port on its south edge under tile (1, 0).
local HALL = Designs.floor(2, 1, Designs.port("output", 1.625, 1))
local COST = Designs.blueprint(HALL).cost

-- A 1x1-tile storage facility: a depot, storage, and input and output
-- ports on its south edge.
local STORE = Designs.floor(1, 1,
	Designs.ability("depot", 0.25, 0.25),
	Designs.storage(8, 0.75, 0.25),
	Designs.port("input", 0.25, 1),
	Designs.port("output", 0.75, 1))

local function facility(ctx, x, y, items)
	local f = Placement.build(ctx, Designs.request(STORE, "N", x, y, "Store"))
	f.storage.capacity = 1000
	for item, n in pairs(items) do
		for _ = 1, n do
			Storage.add(f.storage, item)
		end
	end
	return f
end

local function request(x, y)
	return Designs.request(HALL, "N", x, y, "Hall")
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

test("a site blocks its footprint for placement, the player and every villager", function()
	local ctx = newSession(COST.plank * 2)
	local site = assert(Placement.place(ctx, request(4, 4)))

	assertEqual(site, World.buildingAt(ctx.world, 5, 4))
	assertTrue(World.isBlocked(ctx.world, 4, 4))
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

-- True when tile (x, y) lies on the ring of tiles touching site's footprint.
local function beside(site, x, y)
	local dx = math.max(site.tileX - x, 0, x - (site.tileX + site.width - 1))
	local dy = math.max(site.tileY - y, 0, y - (site.tileY + site.depth - 1))
	return math.max(dx, dy) == 1
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
	assertTrue(beside(site, haul.dest.x, haul.dest.y), "the hauler drops off beside the footprint")

	assertTrue(stepUntil(ctx, function()
		return (site.delivered.counts.plank or 0) == COST.plank
	end, 60 * 120), "everything delivered")
	assertEqual(nil, f.storage.claimed and f.storage.claimed.plank, "no claim left")
	assertEqual(3, StorageFacility.totals(ctx).plank, "only the cost left the facility")
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
	local path = build.villager.walker.path
	local last = path[#path] or { x = math.floor(build.villager.x / TILE), y = math.floor(build.villager.y / TILE) }
	assertTrue(beside(site, last.x, last.y), "the builder works from a tile beside the footprint")
	assertTrue(stepUntil(ctx, function()
		return build.stage == "building"
	end, 60 * 30), "the builder starts building")
	assertTrue(beside(site, math.floor(build.villager.x / TILE), math.floor(build.villager.y / TILE)))

	local built = Site.buildTime(site, Config)
	assertEqual(Config.villagers.buildTime * 2, built, "scaled by the footprint")
	assertTrue(stepUntil(ctx, function()
		return #ctx.pools.buildings == 2
	end, math.ceil(built * 60) + 60 * 10), "the site turned into a building")

	assertEqual(0, #ctx.pools.sites)
	assertEqual(1, build.villager.xp.build, "the builder earned build experience")
	local b = ctx.pools.buildings[2]
	assertEqual("Hall", b.design)
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

-- A 1x1 depot with an input port on its south edge and an output port on
-- its east edge, and no storage.
local PORTED = Designs.floor(1, 1,
	Designs.ability("depot", 0.25, 0.25),
	Designs.port("input", 0.25, 1),
	Designs.port("output", 1, 0.25))

local function portOf(b, kind)
	for _, port in ipairs(b.ports) do
		if port.kind == kind then
			return port
		end
	end
end

test("claimed items in a depot's buffers stay there: not stored, not collected", function()
	local ctx = Session.new(World.new(20, 20), Config, 1)
	local f = Placement.build(ctx, Designs.request(PORTED, "N", 10, 10))
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

test("a builder's work rate aura speeds up build progress; none leaves it unchanged", function()
	local function gain(rate)
		local ctx, f = newSession(COST.plank)
		f.aura.harvestRate = rate
		local site = assert(Placement.place(ctx, request(7, 10)))
		addVillager(ctx, 8, 8)
		assertTrue(stepUntil(ctx, function()
			return site.progress > 0
		end, 60 * 120), "building starts")
		local v = jobOf(ctx, "build").villager
		assertEqual(rate, v.aura.harvestRate, "the builder stands in the facility's reach")
		local before = site.progress
		Session.step(ctx)
		return site.progress - before, v
	end
	local base = gain(0)
	assertNear(1 / 60, base, 1e-9)
	assertNear(2 / 60, gain(1), 1e-9)
end)
