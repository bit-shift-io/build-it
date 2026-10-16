-- Storage facilities (docs/CONTEXT.md "Storage facility", "Depot"):
-- buildings with a depot, the colony's bank. Totals add up every facility;
-- spending takes from the facility nearest the spot first and spills over
-- to the next.
local StorageFacility = require("src.game.components.storage_facility")
local Placement = require("src.game.buildings.placement")
local Session = require("src.game.session")
local World = require("src.game.world")
local Config = require("src.game.config")

local function brick(shape, x, y, extra)
	local b = { x = x, y = y, z = 0, width = 2, depth = 2, shape = shape, rotation = 0, material = "plank", paint = 1 }
	for k, v in pairs(extra or {}) do
		b[k] = v
	end
	return b
end

-- A 1x1-tile design: a depot (or a saw), one storage brick and an output
-- port on the south edge.
local function design(id, ability)
	return {
		id = id,
		name = id,
		versions = {
			{
				width = 1,
				depth = 1,
				bricks = {
					brick(ability == "depot" and "depot" or "saw", 0, 0, { ability = ability }),
					brick("storage", 2, 0, { storage = 8 }),
					brick("output", 0, 3, { port = "output", width = 2, depth = 1 }),
				},
			},
		},
	}
end

local DEPOT = design("d1", "depot")
local CUTTER = design("d2", "saw")

local function newSession()
	return Session.new(World.new(40, 40), Config, 1)
end

local function build(ctx, d, x, y)
	return assert(Placement.build(ctx, { design = d, version = 1, facing = "N", tileX = x, tileY = y }))
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
	local d = {
		id = "d3",
		name = "Store",
		versions = {
			{
				width = 1,
				depth = 1,
				bricks = {
					brick("depot", 0, 0, { ability = "depot" }),
					brick("input", 0, 3, { port = "input", width = 2, depth = 1 }),
					brick("output", 2, 0, { port = "output", width = 2, depth = 1 }),
				},
			},
		},
	}
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
	local d = {
		id = "d4",
		name = "Store",
		versions = {
			{
				width = 1,
				depth = 1,
				bricks = {
					brick("depot", 0, 0, { ability = "depot" }),
					brick("storage", 2, 0, { storage = 8 }),
					brick("input", 0, 3, { port = "input", width = 2, depth = 1 }),
				},
			},
		},
	}
	local b = build(ctx, d, 10, 10)
	local input = b.ports[1]
	Storage.add(input.buffer, "log")
	Storage.add(input.buffer, "stone")

	Session.advance(ctx, 1 / 60)

	assertEqual(0, Storage.total(input.buffer))
	assertEqual(1, b.storage.counts.log)
	assertEqual(1, b.storage.counts.stone)
end)
