local Mover = require("src.game.components.mover")

-- A ctx with only what Mover reads: dt, and a world large enough that no
-- edge is reached.
local function ctxWith(dt)
	return { dt = dt, world = { width = 100, height = 100 }, config = { tileSize = 32 } }
end

local function record(x, y, speed)
	return { x = x, y = y, size = 16, mover = { speed = speed } }
end

test("Mover.apply moves speed * dt along the intent direction", function()
	local r = record(500, 500, 120)
	Mover.apply(r, { x = 1, y = 0 }, ctxWith(1 / 60))
	assertNear(502, r.x)
	assertNear(500, r.y)
end)

test("Mover.apply moves diagonally at the same speed as straight", function()
	local r = record(500, 500, 120)
	Mover.apply(r, { x = 1, y = 1 }, ctxWith(1))
	local dx, dy = r.x - 500, r.y - 500
	assertNear(120, math.sqrt(dx * dx + dy * dy), 0.0001)
	assertNear(dx, dy)
end)

test("Mover.apply stops the record at the world edge, keeping it fully inside", function()
	-- 100 tiles * 32 px = 3200 px wide; a 16 px record's centre stops 8 px in.
	local r = record(3190, 10, 120)
	Mover.apply(r, { x = 1, y = -1 }, ctxWith(1))
	assertNear(3192, r.x)
	assertNear(8, r.y)
end)

local World = require("src.game.world")

local function footprintCtx()
	local world = World.new(10, 10)
	World.addBuilding(world, { tileX = 3, tileY = 0, width = 1, depth = 10, ports = {} })
	return { dt = 0.1, world = world, config = { tileSize = 32 } }
end

test("Mover.apply stops a record at a building footprint", function()
	local r = record(80, 48, 120)
	Mover.apply(r, { x = 1, y = 0 }, footprintCtx())
	assertNear(96 - 8, r.x)
end)

test("Mover.apply moves a record out of a footprint it overlaps but may not enter", function()
	local ctx = footprintCtx()
	-- Centre in the footprint (tile 3 spans x 96..128): walking east leaves it.
	local r = record(110, 48, 120)
	for _ = 1, 10 do
		Mover.apply(r, { x = 1, y = 0 }, ctx)
	end
	assertTrue(r.x - 8 >= 128, "ended past the footprint, at " .. r.x)
end)

test("Mover.apply never lets a record overlapping one footprint into another", function()
	local world = World.new(10, 10)
	World.addBuilding(world, { tileX = 3, tileY = 0, width = 1, depth = 10, ports = {} })
	World.addBuilding(world, { tileX = 4, tileY = 0, width = 1, depth = 10, ports = {} })
	local ctx = { dt = 0.1, world = world, config = { tileSize = 32 } }
	-- Overlaps the tile-2 side of nothing, but sits in tile 3's footprint.
	local r = record(110, 48, 120)
	for _ = 1, 10 do
		Mover.apply(r, { x = 1, y = 0 }, ctx)
	end
	assertTrue(r.x + 8 <= 128, "stopped at the second footprint, at " .. r.x)
end)

-- A finished 1x1 building on tile (3, 1) (px 96..128 x 32..64) facing N,
-- its walk grid 4x4 studs of 8 px: walls round the edge, a 1-stud doorway
-- in the north wall at stud x 1 (px 104..112).
local ROOM = table.concat({
	"x.xx",
	"x..x",
	"x..x",
	"xxxx",
})

local function roomCtx()
	local world = World.new(10, 10)
	local blueprint = { width = 1, depth = 1, walk = { width = 4, depth = 4, cells = ROOM } }
	local building = { tileX = 3, tileY = 1, width = 1, depth = 1, facing = "N", blueprint = blueprint, ports = {} }
	World.addBuilding(world, building)
	return { dt = 1 / 60, world = world, config = { tileSize = 32, walk = { cellsPerTile = 4 } } }, building
end

-- An 8 px record, as the player.
local function walker(x, y, entersBuildings)
	return { x = x, y = y, size = 8, mover = { speed = 120, entersBuildings = entersBuildings } }
end

local function walk(r, intent, ctx, frames)
	for _ = 1, frames do
		Mover.apply(r, intent, ctx)
	end
end

test("Mover.apply walks a record that enters buildings through a doorway and stops it flush at a wall stud", function()
	local ctx = roomCtx()
	local r = walker(108, 20, true)
	walk(r, { x = 0, y = 1 }, ctx, 60)
	-- Stud row 3 (px 56..64) is wall: the record's south edge stops at 56.
	assertNear(52, r.y)
	assertNear(108, r.x)
end)

test("Mover.apply stops a record that may not enter at the footprint edge, doorway or not", function()
	local ctx = roomCtx()
	local r = walker(108, 20, nil)
	walk(r, { x = 0, y = 1 }, ctx, 60)
	assertNear(32 - 4, r.y)
end)

test("Mover.apply keeps a construction site solid to a record that enters buildings", function()
	local ctx, building = roomCtx()
	building.cost = { plank = 4 } -- a site: still to build
	local r = walker(108, 20, true)
	walk(r, { x = 0, y = 1 }, ctx, 60)
	assertNear(32 - 4, r.y)
end)

test("Mover.apply lets a record that enters buildings walk around inside, walls stopping each axis", function()
	local ctx = roomCtx()
	-- Inside, in stud (1, 2) (px 104..112 x 48..56): east wall at stud x 3 (px 120).
	local r = walker(108, 52, true)
	walk(r, { x = 1, y = 0 }, ctx, 60)
	assertNear(120 - 4, r.x)
	walk(r, { x = 0, y = -1 }, ctx, 60)
	-- Stud (2, 0) is north wall (px 32..40): stops at 40.
	assertNear(40 + 4, r.y)
end)

test("Mover.apply lets a record standing in a wall stud walk out of it", function()
	local ctx = roomCtx()
	-- Centred in the west wall stud (0, 2), px 96..104 x 48..56.
	local r = walker(100, 52, true)
	walk(r, { x = 1, y = 0 }, ctx, 30)
	assertTrue(r.x - 4 >= 104, "left the wall, at " .. r.x)
	local out = walker(100, 52, true)
	walk(out, { x = -1, y = 0 }, ctx, 30)
	assertTrue(out.x + 4 <= 96, "walked out of the footprint west, at " .. out.x)
end)

test("Mover.apply walks a record with mover.enter into that one building by its walk grid, walls included", function()
	local ctx, building = roomCtx()
	local r = walker(108, 20, nil)
	r.mover.enter = building
	walk(r, { x = 0, y = 1 }, ctx, 60)
	assertNear(52, r.y, 1e-6, "through the doorway, stopped by the south wall")
	walk(r, { x = 1, y = 0 }, ctx, 60)
	assertNear(120 - 4, r.x, 1e-6, "stopped by the east wall")

	local blocked = walker(116, 20, nil)
	blocked.mover.enter = building
	walk(blocked, { x = 0, y = 1 }, ctx, 60)
	assertNear(32 - 4, blocked.y, 1e-6, "the north wall beside the doorway stops it")

	local other = walker(108, 20, nil)
	other.mover.enter = { tileX = 7, tileY = 0, width = 1, depth = 1, ports = {} }
	walk(other, { x = 0, y = 1 }, ctx, 60)
	assertNear(32 - 4, other.y, 1e-6, "another building's footprint stays solid")
end)
