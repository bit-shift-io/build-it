-- Storage facilities (docs/CONTEXT.md "Storage facility", "Depot"):
-- buildings with a depot, the colony's bank. Totals add up every facility;
-- spending takes from the facility nearest the spot first and spills over
-- to the next.
local StorageFacility = require("src.game.components.storage_facility")
local Placement = require("src.game.buildings.placement")
local Session = require("src.game.session")
local World = require("src.game.world")
local Config = require("src.game.config")

local Designs = require("tests.support.designs")

-- A 1x1-tile design: a depot (or a saw), storage for 8 and an output port
-- on the south edge.
local function design(ability)
	return Designs.floor(1, 1,
		Designs.ability(ability, 0.25, 0.25),
		Designs.storage(8, 0.75, 0.25),
		Designs.port("output", 0.25, 1))
end

local DEPOT = design("depot")
local CUTTER = design("saw")

local function newSession()
	return Session.new(World.new(40, 40), Config, 1)
end

local function build(ctx, d, x, y)
	return assert(Placement.build(ctx, Designs.request(d, "N", x, y)))
end

test("only buildings with a depot are storage facilities, in pool order", function()
	local ctx = newSession()
	local a = build(ctx, DEPOT, 2, 2)
	build(ctx, CUTTER, 6, 2)
	local b = build(ctx, DEPOT, 10, 2)

	local all = StorageFacility.all(ctx)
	assertEqual(2, #all)
	assertEqual(a, all[1])
	assertEqual(b, all[2])
end)

local Storage = require("src.game.components.storage")

local function stock(b, item, n)
	for _ = 1, n do
		Storage.add(b.storage, item)
	end
end

test("totals add up storage and port buffers across every facility, and skip other buildings", function()
	local ctx = newSession()
	local a = build(ctx, DEPOT, 2, 2)
	local cutter = build(ctx, CUTTER, 6, 2)
	local b = build(ctx, DEPOT, 10, 2)
	stock(a, "plank", 3)
	stock(b, "plank", 2)
	stock(b, "stone", 1)
	Storage.add(b.ports[1].buffer, "log")
	stock(cutter, "plank", 5)

	local totals = StorageFacility.totals(ctx)
	assertEqual(5, totals.plank)
	assertEqual(1, totals.stone)
	assertEqual(1, totals.log)
	assertTrue(StorageFacility.has(ctx, { plank = 5, log = 1 }))
	assertFalse(StorageFacility.has(ctx, { plank = 6 }))
end)

test("claiming takes from the facility nearest the spot first, then spills to the next", function()
	local ctx = newSession()
	local far = build(ctx, DEPOT, 2, 2)
	local near = build(ctx, DEPOT, 20, 2)
	stock(far, "plank", 4)
	stock(near, "plank", 3)

	local claims = StorageFacility.claim(ctx, { plank = 5 }, 22, 2)

	assertEqual(2, #claims)
	assertEqual(near, claims[1].building)
	assertEqual(3, claims[1].count, "nearest claimed first")
	assertEqual(far, claims[2].building)
	assertEqual(2, claims[2].count, "the rest from the next")
	assertEqual(3, near.storage.counts.plank, "claimed stock stays in storage")
	assertEqual(2, StorageFacility.totals(ctx).plank, "and is not available")
	assertEqual(5, StorageFacility.claimed(ctx).plank)
end)

local Ports = require("src.game.components.ports")
local Inventory = require("src.game.components.inventory")

test("a depot's input accepts every item", function()
	local ctx = newSession()
	local d = Designs.floor(1, 1,
		Designs.ability("depot", 0.25, 0.25),
		Designs.port("input", 0.25, 1),
		Designs.port("output", 0.75, 0))
	local b = build(ctx, d, 5, 5)
	local input = b.ports[1]
	assertEqual("input", input.kind)
	assertTrue(Ports.accepts(b, "log"))
	assertTrue(Ports.accepts(b, "stone"))

	local inv = Inventory.new({ log = 1, stone = 1 })
	Ports.deliver(input, b, inv)
	assertEqual(1, input.buffer.counts.log)
	assertEqual(1, input.buffer.counts.stone)
end)

test("a depot moves what reaches its input into the facility's storage, so the input frees up", function()
	local ctx = newSession()
	local d = Designs.floor(1, 1,
		Designs.ability("depot", 0.25, 0.25),
		Designs.storage(8, 0.75, 0.25),
		Designs.port("input", 0.25, 1))
	local b = build(ctx, d, 10, 10)
	local input = b.ports[1]
	Storage.add(input.buffer, "log")
	Storage.add(input.buffer, "stone")

	Session.advance(ctx, 1 / 60)

	assertEqual(0, Storage.total(input.buffer))
	assertEqual(1, b.storage.counts.log)
	assertEqual(1, b.storage.counts.stone)
end)

test("fill is held over capacity as a whole percent rounded down; port buffers and incoming are ignored", function()
	local ctx = newSession()
	local b = build(ctx, DEPOT, 2, 2)
	b.storage.capacity = 200
	local f = StorageFacility.fill(b)
	assertEqual(0, f.percent)
	assertEqual(0, f.held)
	assertEqual(200, f.capacity)

	stock(b, "plank", 199)
	assertEqual(99, StorageFacility.fill(b).percent)
	Storage.add(b.ports[1].buffer, "log")
	b.storage.incoming = 50
	assertEqual(99, StorageFacility.fill(b).percent)

	b.storage.incoming = 0
	stock(b, "plank", 1)
	assertEqual(100, StorageFacility.fill(b).percent)

	b.storage.capacity = 0
	assertEqual(nil, StorageFacility.fill(b))
end)

test("totalFill sums facilities before dividing, skipping other buildings and dead ones", function()
	local ctx = newSession()
	local a = build(ctx, DEPOT, 2, 2)
	local b = build(ctx, DEPOT, 10, 2)
	local cutter = build(ctx, CUTTER, 6, 2)
	local gone = build(ctx, DEPOT, 14, 2)
	a.storage.capacity = 100
	b.storage.capacity = 300
	gone.storage.capacity = 100
	cutter.storage.capacity = 100
	stock(a, "plank", 100)
	stock(cutter, "plank", 100)
	stock(gone, "plank", 100)
	gone.dead = true

	assertEqual(25, StorageFacility.totalFill(ctx))

	a.storage.capacity = 0
	b.storage.capacity = 0
	assertEqual(nil, StorageFacility.totalFill(ctx))
end)

test("short flags the items of a cost the totals can't cover, missing ones included", function()
	local short = StorageFacility.short({ plank = 10, stone = 2, glass = 1 }, { plank = 3, stone = 2 })
	assertEqual(true, short.plank)
	assertEqual(true, short.glass)
	assertEqual(nil, short.stone)
	assertEqual(nil, next(StorageFacility.short({}, { plank = 1 })))
end)
