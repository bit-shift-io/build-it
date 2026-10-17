-- The walker component (src/game/components/walker.lua): a record given a
-- target tile follows a path to it through Mover, then stops.
local Walker = require("src.game.components.walker")
local World = require("src.game.world")
local Config = require("src.game.config")

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

test("a walker goes round a footprint, through its own building with mover.enter; an unreachable target leaves it standing", function()
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

	local inside = walkerAt(1, 2)
	inside.mover.enter = b
	assertTrue(Walker.goTo(inside, ctx, 8, 2))
	assertEqual(7, #inside.walker.path, "the straight line through the footprint")
	for _ = 1, 60 * 5 do
		Walker.step(inside, ctx)
	end
	assertNear(8.5 * TILE, inside.x)

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
