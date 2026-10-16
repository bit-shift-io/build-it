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
		mover = { speed = Config.villagers.speed, throughBuildings = true },
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

test("a villager walker crosses a building footprint; an unreachable target leaves it standing", function()
	local world = World.new(10, 5)
	World.addBuilding(world, { tileX = 4, tileY = 0, width = 2, depth = 5, ports = {} })
	local ctx = ctxWith(world)
	local r = walkerAt(1, 2)

	assertTrue(Walker.goTo(r, ctx, 8, 2))
	assertEqual(7, #r.walker.path, "the straight line through the footprint")
	for _ = 1, 60 * 5 do
		Walker.step(r, ctx)
	end
	assertNear(8.5 * TILE, r.x)

	World.setTerrain(world, 0, 0, "water")
	assertFalse(Walker.goTo(r, ctx, 0, 0))
	assertTrue(Walker.idle(r.walker))
end)
