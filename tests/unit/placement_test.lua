-- Placing a building (docs/CONTEXT.md "Building", "Footprint", "Port"):
-- footprint and port tiles per facing, every reason a placement is refused,
-- and the cost paid once.
local Placement = require("src.game.buildings.placement")
local Config = require("src.game.config")
local Designs = require("tests.support.designs")

-- A 3x2 tile design, asymmetric: an input port on the west edge in tile
-- (0, 1), an output port on the north edge in tile (2, 0).
local ASYM = Designs.floor(3, 2, Designs.port("input", 0.125, 1.375), Designs.port("output", 2.375, 0.125))

test("the footprint is the blueprint's, turned on E and W", function()
	local v = Designs.blueprint(ASYM)
	local w, d = Placement.footprint(v, "N")
	assertEqual(3, w)
	assertEqual(2, d)
	w, d = Placement.footprint(v, "E")
	assertEqual(2, w)
	assertEqual(3, d)
	w, d = Placement.footprint(v, "S")
	assertEqual(3, w)
	assertEqual(2, d)
	w, d = Placement.footprint(v, "W")
	assertEqual(2, w)
	assertEqual(3, d)
end)

-- Ports in role order: { kind, side, x, y }, x/y the world tile the port
-- faces for a building with its footprint's north-west tile on (10, 10).
local function portsAt(facing)
	return Placement.ports(Designs.blueprint(ASYM), facing, 10, 10)
end

local function assertPort(port, kind, side, x, y)
	assertEqual(kind, port.kind)
	assertEqual(side, port.side, kind .. " side")
	assertEqual(x, port.x, kind .. " x")
	assertEqual(y, port.y, kind .. " y")
end

test("port tiles lie just outside the footprint edge in every facing", function()
	local n = portsAt("N")
	assertEqual(2, #n)
	assertPort(n[1], "input", "W", 9, 11)
	assertPort(n[2], "output", "N", 12, 9)

	local e = portsAt("E")
	assertPort(e[1], "input", "N", 10, 9)
	assertPort(e[2], "output", "E", 12, 12)

	local s = portsAt("S")
	assertPort(s[1], "input", "E", 13, 10)
	assertPort(s[2], "output", "S", 10, 12)

	local w = portsAt("W")
	assertPort(w[1], "input", "S", 11, 13)
	assertPort(w[2], "output", "W", 9, 10)
end)

test("a port faces the tile under its position along its edge", function()
	local ports = Placement.ports(Designs.blueprint(Designs.floor(2, 1, Designs.port("output", 1.25, 0))), "N", 0, 0)
	assertPort(ports[1], "output", "N", 1, -1)
end)

local Session = require("src.game.session")
local World = require("src.game.world")
local Storage = require("src.game.components.storage")
local StorageFacility = require("src.game.components.storage_facility")

-- A 1x1-tile storage facility: a depot and storage, no ports.
local STORE = Designs.floor(1, 1, Designs.ability("depot", 0.25, 0.25), Designs.storage(8, 0.75, 0.25), Designs.storage(8, 0.25, 0.75))

-- A facility on tile (x, y) holding `items` ({ [item] = n }).
local function facility(ctx, x, y, items)
	local f = assert(Placement.build(ctx, Designs.request(STORE, "N", x, y, "Store")))
	f.storage.capacity = 1000
	for item, n in pairs(items) do
		for _ = 1, n do
			Storage.add(f.storage, item)
		end
	end
	return f
end

-- A 20x20 session with one facility in the south-east corner holding the
-- stockpile.
local function newSession()
	local ctx = Session.new(World.new(20, 20), Config, 1)
	local f = facility(ctx, 19, 19, Config.stockpile)
	return ctx, f
end

-- One step with player 1 asking to place ASYM, named "Hall".
local function place(ctx, facing, x, y)
	ctx.intents[1] = { x = 0, y = 0, place = Designs.request(ASYM, facing, x, y, "Hall") }
	Session.advance(ctx, 1 / 60)
	ctx.intents[1] = nil
end

test("placing creates a construction site with the design, blueprint, facing and turned footprint", function()
	local ctx = newSession()
	place(ctx, "E", 2, 3)

	assertEqual(1, #ctx.pools.buildings, "only the facility: no building yet")
	local site = ctx.pools.sites[1]
	assertEqual("Hall", site.design)
	assertEqual(Designs.blueprint(ASYM), site.blueprint)
	assertEqual("E", site.facing)
	assertEqual(2, site.tileX)
	assertEqual(3, site.tileY)
	assertEqual(2, site.width)
	assertEqual(3, site.depth)
end)

test("a building has the design, blueprint, facing and an empty buffer per port", function()
	local ctx = newSession()
	local b = Placement.build(ctx, Designs.request(ASYM, "E", 2, 3, "Hall"))

	assertEqual("Hall", b.design)
	assertEqual(Designs.blueprint(ASYM), b.blueprint)
	assertEqual("E", b.facing)
	assertEqual(2, b.tileX)
	assertEqual(3, b.tileY)
	assertEqual(2, b.width)
	assertEqual(3, b.depth)
	assertEqual(2, #b.ports)
	assertEqual("input", b.ports[1].kind)
	assertEqual(2, b.ports[1].x)
	assertEqual(2, b.ports[1].y)
	assertEqual(nil, next(b.ports[1].buffer.counts), "buffer starts empty")
	assertEqual(nil, next(b.ports[2].buffer.counts), "buffer starts empty")
end)

test("a building occupies its footprint, blocks it and marks its port tiles", function()
	local ctx = newSession()
	local b = Placement.build(ctx, Designs.request(ASYM, "E", 2, 3, "Hall"))

	for y = 3, 5 do
		for x = 2, 3 do
			assertEqual(b, World.buildingAt(ctx.world, x, y))
			assertTrue(World.isBlocked(ctx.world, x, y))
		end
	end
	assertEqual(nil, World.buildingAt(ctx.world, 4, 3))
	assertFalse(World.isBlocked(ctx.world, 4, 3))

	assertEqual(b.ports[1], World.portAt(ctx.world, 2, 2))
	assertEqual(b.ports[2], World.portAt(ctx.world, 4, 5))
	assertFalse(World.isBlocked(ctx.world, 2, 2), "port tiles stay walkable")
end)

local function stored(ctx, item)
	return StorageFacility.totals(ctx)[item] or 0
end

test("placing takes the cost off the storage totals, once, never from the inventory", function()
	local ctx = newSession()
	local c = ctx.pools.characters[1]
	c.inventory.counts.plank = 500
	local before = stored(ctx, "plank")
	local cost = Designs.blueprint(ASYM).cost.plank

	place(ctx, "N", 2, 3)
	Session.advance(ctx, 1 / 60)
	Session.advance(ctx, 1 / 60)

	assertEqual(before - cost, stored(ctx, "plank"))
	assertEqual(Config.stockpile.stone, stored(ctx, "stone"))
	assertEqual(500, c.inventory.counts.plank)
end)

test("placing claims from the facility nearest the footprint first, then the next", function()
	local ctx = Session.new(World.new(20, 20), Config, 1)
	local cost = Designs.blueprint(ASYM).cost.plank
	local far = facility(ctx, 19, 19, { plank = cost })
	local near = facility(ctx, 0, 0, { plank = cost - 1 })

	place(ctx, "N", 2, 3)

	assertEqual(1, #ctx.pools.sites, "placed")
	assertEqual(cost - 1, near.storage.claimed.plank, "all the nearest holds")
	assertEqual(1, far.storage.claimed.plank, "one plank from the far one")
	assertEqual(cost - 1, near.storage.counts.plank, "claimed stock stays until hauled")
end)

local function request(facing, x, y)
	return Designs.request(ASYM, facing, x, y, "Hall")
end

-- Placement.check's answer for ASYM facing N at (5, 5): footprint
-- (5..7, 5..6), input port tile (4, 6), output port tile (7, 4).
local function check(ctx, x, y)
	return Placement.check(ctx, request("N", x or 5, y or 5))
end

test("a placement on clear grass with the cost in storage is valid", function()
	local ctx = newSession()
	local ok, reason = check(ctx)
	assertTrue(ok)
	assertEqual(nil, reason)
end)

test("a placement is refused with why, and nothing is placed or paid", function()
	local cases = {
		{
			reason = "water",
			setup = function(ctx)
				World.setTerrain(ctx.world, 7, 6, "water")
			end,
		},
		{
			reason = "node",
			setup = function(ctx)
				World.addNode(ctx.world, { id = 1, kind = "rock", tileX = 6, tileY = 5, variant = 1, stage = 1, amount = 1 })
			end,
		},
		{
			reason = "building",
			setup = function(ctx)
				place(ctx, "N", 7, 1) -- footprint 7..9 x 1..2
			end,
			x = 6,
			y = 2,
		},
		{
			reason = "port blocked",
			setup = function(ctx)
				World.setTerrain(ctx.world, 4, 6, "water")
			end,
		},
		{
			reason = "port blocked",
			setup = function() end,
			x = 0,
			y = 5,
		},
		{
			reason = "outside",
			setup = function() end,
			x = 18,
			y = 5,
		},
		{
			reason = "unaffordable",
			setup = function(_, f)
				f.storage.counts.plank = Designs.blueprint(ASYM).cost.plank - 1
			end,
		},
	}
	for _, case in ipairs(cases) do
		local ctx, f = newSession()
		case.setup(ctx, f)
		local built, sites = #ctx.pools.buildings, #ctx.pools.sites
		local planks = stored(ctx, "plank")

		local ok, reason = check(ctx, case.x, case.y)
		assertFalse(ok, case.reason .. ": expected refusal")
		assertEqual(case.reason, reason)

		place(ctx, "N", case.x or 5, case.y or 5)
		assertEqual(built, #ctx.pools.buildings, case.reason .. ": nothing placed")
		assertEqual(sites, #ctx.pools.sites, case.reason .. ": no site")
		assertEqual(planks, stored(ctx, "plank"), case.reason .. ": nothing paid")
	end
end)

test("each function brick knows its tile inside the footprint, turned by facing", function()
	local mill = Designs.floor(3, 2, Designs.ability("sawbench", 2.5, 1.5))
	-- The bench stands on tile (2, 1) of the 3x2 footprint facing N.
	for facing, at in pairs({ N = { 2, 1 }, E = { 0, 2 }, S = { 0, 0 }, W = { 1, 0 } }) do
		local ctx = Session.new(World.new(20, 20), Config, 1)
		local b = Placement.build(ctx, Designs.request(mill, facing, 5, 6))
		local fb = b.functionBricks[1]
		assertEqual(5 + at[1], fb.tileX, facing .. " x")
		assertEqual(6 + at[2], fb.tileY, facing .. " y")
	end
end)

-- Replace (docs/CONTEXT.md "Replace"): a request with `replaces` set to a
-- building turns that building back into a site for another blueprint.

-- A 1x1 design with a saw: the old building replaced below.
local SMALL = Designs.floor(1, 1, Designs.ability("saw", 0.5, 0.5))
-- A 2x2 design with a saw and more floor: the new one, costing more planks.
local BIG = Designs.floor(2, 2, Designs.ability("saw", 0.5, 0.5))

local function replaceRequest(old, text, facing, x, y)
	local r = Designs.request(text, facing, x, y, "Big")
	r.replaces = old
	return r
end

test("a replacement costs the new blueprint less the old one, never below zero", function()
	local ctx = newSession()
	local old = Placement.build(ctx, Designs.request(BIG, "N", 5, 5))
	old.blueprint = { cost = { plank = 3, stone = 50 } }
	local r = replaceRequest(old, BIG, "N", 5, 5)
	r.blueprint = { cost = { plank = 10, stone = 20, log = 2 } }

	local cost = Placement.cost(r)
	assertEqual(7, cost.plank)
	assertEqual(nil, cost.stone, "more stone in the old one: nothing to pay")
	assertEqual(2, cost.log)
end)

test("a replacement may stand on the replaced building's footprint", function()
	local ctx = newSession()
	local old = Placement.build(ctx, Designs.request(SMALL, "N", 5, 5))
	-- BIG on (5..6, 5..6) covers the old footprint (5, 5).
	local ok, reason = Placement.check(ctx, replaceRequest(old, BIG, "N", 5, 5))
	assertTrue(ok, tostring(reason))
	assertFalse(Placement.check(ctx, Designs.request(BIG, "N", 5, 5)), "a plain placement there is refused")
end)

test("a replacement is still refused by another building", function()
	local ctx = newSession()
	local old = Placement.build(ctx, Designs.request(SMALL, "N", 5, 5))
	Placement.build(ctx, Designs.request(SMALL, "N", 6, 6))
	local ok, reason = Placement.check(ctx, replaceRequest(old, BIG, "N", 5, 5))
	assertFalse(ok)
	assertEqual("building", reason)
end)

test("a replacement is affordable when storage covers only the missing materials", function()
	local ctx, f = newSession()
	local old = Placement.build(ctx, Designs.request(SMALL, "N", 5, 5))
	local missing = Placement.cost(replaceRequest(old, BIG, "N", 5, 5))
	assertTrue(missing.plank < Designs.blueprint(BIG).cost.plank, "the old planks count")
	f.storage.counts.plank = missing.plank
	assertTrue(Placement.check(ctx, replaceRequest(old, BIG, "N", 5, 5)))
	f.storage.counts.plank = missing.plank - 1
	local ok, reason = Placement.check(ctx, replaceRequest(old, BIG, "N", 5, 5))
	assertFalse(ok)
	assertEqual("unaffordable", reason)
end)

test("replacing turns the building into a site that claims only the missing materials", function()
	local ctx, f = newSession()
	local old = Placement.build(ctx, Designs.request(SMALL, "N", 5, 5))
	local r = replaceRequest(old, BIG, "N", 5, 5)
	local missing = Placement.cost(r)

	ctx.intents[1] = { x = 0, y = 0, place = r }
	Session.advance(ctx, 1 / 60)
	ctx.intents[1] = nil

	assertEqual(1, #ctx.pools.buildings, "the old building despawned; the facility stays")
	assertEqual(f, ctx.pools.buildings[1])
	assertTrue(old.dead)
	local site = ctx.pools.sites[1]
	assertEqual("Big", site.design)
	assertEqual(missing.plank, site.cost.plank)
	assertEqual(missing.plank, f.storage.claimed.plank)
	for y = 5, 6 do
		for x = 5, 6 do
			assertEqual(site, World.buildingAt(ctx.world, x, y))
		end
	end
end)

-- A 2x1 woodcutter with storage and an output port on its south edge.
local STOCKED = Designs.floor(2, 1, Designs.ability("saw", 0.5, 0.5), Designs.storage(8, 1.5, 0.5), Designs.port("output", 0.5, 1))

local function fill(store, item, n)
	store.capacity = math.max(store.capacity, n)
	for _ = 1, n do
		Storage.add(store, item)
	end
end

local function replaceAt(ctx, old)
	ctx.intents[1] = { x = 0, y = 0, place = replaceRequest(old, BIG, "N", old.tileX, old.tileY) }
	Session.advance(ctx, 1 / 60)
	ctx.intents[1] = nil
end

test("a replaced building's storage and buffers go to the nearest storage facility, then the next", function()
	local ctx, far = newSession()
	local old = Placement.build(ctx, Designs.request(STOCKED, "N", 5, 5))
	fill(old.storage, "log", 6)
	fill(old.ports[1].buffer, "log", 2)
	local near = facility(ctx, 3, 3, {})
	near.storage.capacity = 5
	local farLogs = far.storage.counts.log or 0

	replaceAt(ctx, old)

	assertEqual(5, near.storage.counts.log, "the nearest fills up")
	assertEqual(farLogs + 3, far.storage.counts.log, "the rest goes to the next")
end)

test("what no storage facility has room for is lost", function()
	local ctx, f = newSession()
	local old = Placement.build(ctx, Designs.request(STOCKED, "N", 5, 5))
	fill(old.storage, "log", 6)
	f.storage.capacity = Storage.total(f.storage) + 4

	replaceAt(ctx, old)

	assertEqual(4, (f.storage.counts.log or 0) - (Config.stockpile.log or 0))
	assertEqual(0, Storage.room(f.storage))
end)

test("a storage facility can't be replaced", function()
	local ctx, f = newSession()
	local ok, reason = Placement.check(ctx, replaceRequest(f, BIG, "N", 18, 18))
	assertFalse(ok)
	assertEqual("storage facility", reason)
end)

test("a building already replaced can't be replaced again", function()
	local ctx = newSession()
	local old = Placement.build(ctx, Designs.request(SMALL, "N", 5, 5))
	replaceAt(ctx, old)
	local sites = #ctx.pools.sites
	replaceAt(ctx, old)
	assertEqual(sites, #ctx.pools.sites)
	local ok, reason = Placement.check(ctx, replaceRequest(old, BIG, "N", 5, 5))
	assertFalse(ok)
	assertEqual("gone", reason)
end)
