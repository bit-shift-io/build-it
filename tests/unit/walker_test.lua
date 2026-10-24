-- The walker component (src/game/components/walker.lua): a record given a
-- target tile follows a path to it through Mover, then stops; one sent
-- into a building walks in through a doorway by its walk grid.
local Walker = require("src.game.components.walker")
local World = require("src.game.world")
local Config = require("src.game.config")
local Walls = require("tests.support.walls")

local TILE = Config.tileSize

local function ctxWith(world)
	return { dt = 1 / 60, world = world, config = Config }
end

local function walkerAt(tileX, tileY)
	return {
		x = (tileX + 0.5) * TILE,
		y = (tileY + 0.5) * TILE,
		size = Config.villagers.size,
		mover = { speed = Config.villagers.speed },
		walker = Walker.new(),
	}
end

local function tileOf(r)
	return math.floor(r.x / TILE), math.floor(r.y / TILE)
end

test("a walker sent to a tile walks around water, reaches the tile's centre and stops", function()
	local world = World.new(12, 12)
	for y = 0, 9 do
		World.setTerrain(world, 5, y, "water")
	end
	local ctx = ctxWith(world)
	local r = walkerAt(1, 1)

	assertTrue(Walker.goTo(r, ctx, 9, 1), "expected a route")
	assertFalse(Walker.idle(r.walker))
	for _ = 1, 60 * 20 do
		local x, y = tileOf(r)
		assertFalse(World.isBlocked(world, x, y), "walked onto blocked tile " .. x .. "," .. y)
		Walker.step(r, ctx)
	end

	assertTrue(Walker.idle(r.walker), "expected the walk to end")
	assertNear(9.5 * TILE, r.x)
	assertNear(1.5 * TILE, r.y)
	local x, y = r.x, r.y
	Walker.step(r, ctx)
	assertEqual(x, r.x)
	assertEqual(y, r.y)
end)

test("a walker goes round a footprint; an unreachable target leaves it standing", function()
	local world = World.new(10, 5)
	local b = { tileX = 4, tileY = 0, width = 2, depth = 4, ports = {} }
	World.addBuilding(world, b)
	local ctx = ctxWith(world)
	local r = walkerAt(1, 2)

	assertTrue(Walker.goTo(r, ctx, 8, 2))
	local viaGap = false
	for _, p in ipairs(r.walker.path) do
		viaGap = viaGap or p.y == 4
	end
	assertTrue(viaGap, "the route detours through the gap below the footprint")
	for _ = 1, 60 * 5 do
		local x, y = tileOf(r)
		assertFalse(World.buildingAt(world, x, y) ~= nil, "walked onto the footprint at " .. x .. "," .. y)
		Walker.step(r, ctx)
	end
	assertNear(8.5 * TILE, r.x)

	World.setTerrain(world, 0, 0, "water")
	assertFalse(Walker.goTo(r, ctx, 0, 0))
	assertTrue(Walker.idle(r.walker))
end)

test("a walker that starts inside a footprint it may not enter walks out and never into another", function()
	local world = World.new(12, 5)
	World.addBuilding(world, { tileX = 3, tileY = 0, width = 3, depth = 5, ports = {} })
	World.addBuilding(world, { tileX = 8, tileY = 0, width = 1, depth = 4, ports = {} })
	local ctx = ctxWith(world)
	local r = walkerAt(4, 2)
	assertTrue(Walker.goTo(r, ctx, 10, 2))
	for _ = 1, 60 * 8 do
		Walker.step(r, ctx)
	end
	assertNear(10.5 * TILE, r.x)
	assertNear(2.5 * TILE, r.y)
end)

test("a footprint placed across the path makes the walker repath around it", function()
	local world = World.new(12, 12)
	local ctx = ctxWith(world)
	local r = walkerAt(1, 5)
	assertTrue(Walker.goTo(r, ctx, 9, 5))
	World.addBuilding(world, { tileX = 5, tileY = 3, width = 1, depth = 5, ports = {} })
	for _ = 1, 60 * 20 do
		Walker.step(r, ctx)
		local x, y = tileOf(r)
		assertFalse(World.buildingAt(world, x, y) ~= nil, "walked onto the footprint")
	end
	assertTrue(Walker.idle(r.walker))
	assertFalse(Walker.failed(r.walker))
	local x, y = tileOf(r)
	assertEqual(9, x)
	assertEqual(5, y)
end)

test("a footprint that walls the target off ends the walk as failed, not arrived", function()
	local world = World.new(12, 12)
	local ctx = ctxWith(world)
	local r = walkerAt(1, 5)
	assertTrue(Walker.goTo(r, ctx, 9, 5))
	World.addBuilding(world, { tileX = 5, tileY = 0, width = 1, depth = 12, ports = {} })
	for _ = 1, 60 * 5 do
		Walker.step(r, ctx)
	end
	assertTrue(Walker.idle(r.walker))
	assertTrue(Walker.failed(r.walker))
	assertTrue(Walker.goTo(r, ctx, 2, 5))
	assertFalse(Walker.failed(r.walker), "a new walk clears the failure")
end)

local Session = require("src.game.session")
local Placement = require("src.game.buildings.placement")
local Designs = require("tests.support.designs")

local STUD = TILE / Config.walk.cellsPerTile

-- A walled 2x2 room, walls a voxel thick and body high: a 2-stud door in
-- the middle of the south wall, and an inner wall along row 4 from the
-- west wall to column 5, so the way from the door to the north-west
-- corner goes round its east end. A sawbench role (no geometry) at
-- (0.5, 0.5).
--   xxxxxxxx
--   x......x
--   x......x
--   x......x
--   xxxxxx.x
--   x......x
--   x......x
--   xxx..xxx
local function wall(x, y, w, d)
	return string.format("box{ size = { %g, %g, 0.5 }, transform = { move = { %g, %g, 0.0625 } } }", w, d, x, y)
end
local ROOM = Designs.floor(2, 2,
	wall(0, 0, 2, 0.0625), wall(0, 0, 0.0625, 2), wall(1.9375, 0, 0.0625, 2),
	wall(0, 1.9375, 0.75, 0.0625), wall(1.25, 1.9375, 0.75, 0.0625),
	wall(0, 1, 1.5, 0.0625),
	Designs.ability("sawbench", 0.5, 0.5))

local function inWall(r, b)
	return Walls.under(r, b, Config) ~= nil
end

test("a walker goes into a building through its door, a tile leg then a stud leg, without stopping", function()
	local ctx = Session.new(World.new(12, 12), Config, 1)
	ctx.dt = 1 / 60
	local b = Placement.build(ctx, Designs.request(ROOM, "N", 4, 2))
	local r = walkerAt(1, 9)
	r.mover.enter = b

	assertTrue(Walker.goInside(r, ctx, b, b.tileX + 0.5, b.tileY + 0.5), "expected a route in")
	local wentInside = false
	for _ = 1, 60 * 20 do
		if Walker.idle(r.walker) then
			break
		end
		local x, y = r.x, r.y
		Walker.step(r, ctx)
		assertFalse(x == r.x and y == r.y, "stood still mid-walk at " .. r.x .. "," .. r.y)
		assertFalse(inWall(r, b), "overlaps a wall at " .. r.x .. "," .. r.y)
		wentInside = wentInside or World.buildingAt(ctx.world, math.floor(r.x / TILE), math.floor(r.y / TILE)) == b
	end
	assertTrue(Walker.idle(r.walker), "expected the walk to end")
	assertTrue(wentInside)
	-- The open cell nearest the brick point, first in row order: (1, 1).
	assertNear((b.tileX * 4 + 1.5) * STUD, r.x)
	assertNear((b.tileY * 4 + 1.5) * STUD, r.y)
end)

test("a walker inside a building walks out through its door, then over tiles round to the far side", function()
	local ctx = Session.new(World.new(12, 12), Config, 1)
	ctx.dt = 1 / 60
	local b = Placement.build(ctx, Designs.request(ROOM, "N", 4, 2))
	local r = walkerAt(1, 1)
	r.x, r.y = (b.tileX * 4 + 1.5) * STUD, (b.tileY * 4 + 1.5) * STUD
	r.mover.enter = b

	assertTrue(Walker.goTo(r, ctx, 5, 0), "expected a route out")
	local leftBySouth = false
	for _ = 1, 60 * 20 do
		if Walker.idle(r.walker) then
			break
		end
		Walker.step(r, ctx)
		assertFalse(inWall(r, b), "overlaps a wall at " .. r.x .. "," .. r.y)
		leftBySouth = leftBySouth or r.y > (b.tileY + b.depth) * TILE
	end
	assertTrue(Walker.idle(r.walker), "expected the walk to end")
	assertTrue(leftBySouth, "left by the south door")
	assertNear(5.5 * TILE, r.x)
	assertNear(0.5 * TILE, r.y)
end)

-- ROOM's walls with no inner wall and a 2-stud door in the north wall too;
-- the brick by the north door.
local TWO_DOORS = Designs.floor(2, 2,
	wall(0, 0, 0.75, 0.0625), wall(1.25, 0, 0.75, 0.0625),
	wall(0, 0, 0.0625, 2), wall(1.9375, 0, 0.0625, 2),
	wall(0, 1.9375, 0.75, 0.0625), wall(1.25, 1.9375, 0.75, 0.0625),
	Designs.ability("sawbench", 1, 0.375))

test("a walker goes in by the doorway nearest its target cell, not the one nearest itself", function()
	local ctx = Session.new(World.new(12, 12), Config, 1)
	ctx.dt = 1 / 60
	local b = Placement.build(ctx, Designs.request(TWO_DOORS, "N", 4, 2))
	local r = walkerAt(5, 6)
	r.mover.enter = b

	assertTrue(Walker.goInside(r, ctx, b, b.tileX + 1, b.tileY + 0.375))
	local north = false
	for _ = 1, 60 * 20 do
		if Walker.idle(r.walker) then
			break
		end
		Walker.step(r, ctx)
		assertFalse(inWall(r, b), "overlaps a wall at " .. r.x .. "," .. r.y)
		north = north or r.y < b.tileY * TILE
	end
	assertTrue(Walker.idle(r.walker))
	assertTrue(north, "came round to the north door")
	assertEqual(b, World.buildingAt(ctx.world, math.floor(r.x / TILE), math.floor(r.y / TILE)))
end)
