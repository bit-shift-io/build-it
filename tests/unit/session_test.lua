local Session = require("src.game.session")
local Config = require("src.game.config")

local function newSession(world)
	return Session.new(world or { width = 20, height = 10 }, Config, 1)
end

test("Session.new spawns one character for player 1 at the world centre", function()
	local ctx = newSession()
	local c = ctx.pools.characters[1]
	assertEqual(1, #ctx.pools.characters)
	assertEqual(1, c.player)
	assertNear(20 * Config.tileSize / 2, c.x)
	assertNear(10 * Config.tileSize / 2, c.y)
end)

test("Session.step moves the character by speed * dt per step along its intent", function()
	local ctx = newSession()
	local c = ctx.pools.characters[1]
	local startX, startY = c.x, c.y
	ctx.dt = 1 / 60
	ctx.intents[1] = { x = 0, y = 1 }

	for _ = 1, 3 do
		Session.step(ctx)
	end

	assertNear(startX, c.x)
	assertNear(startY + 3 * Config.character.speed / 60, c.y, 0.000001)
end)

test("Session.step leaves the character still when no intent is set", function()
	local ctx = newSession()
	local c = ctx.pools.characters[1]
	local startX, startY = c.x, c.y
	ctx.dt = 1 / 60

	Session.step(ctx)

	assertNear(startX, c.x)
	assertNear(startY, c.y)
end)

test("Session.step stops the character at the world edge", function()
	local ctx = newSession({ width = 4, height = 4 })
	local c = ctx.pools.characters[1]
	ctx.dt = 1 / 60
	ctx.intents[1] = { x = -1, y = 0 }

	for _ = 1, 600 do
		Session.step(ctx)
	end

	assertNear(Config.character.size / 2, c.x)
end)

test("Session.advance sets dt, advances time and steps once", function()
	local ctx = newSession()
	local c = ctx.pools.characters[1]
	local startX = c.x
	ctx.intents[1] = { x = 1, y = 0 }

	Session.advance(ctx, 1 / 60)
	Session.advance(ctx, 1 / 60)

	assertNear(1 / 60, ctx.dt)
	assertNear(2 / 60, ctx.time)
	assertNear(startX + 2 * Config.character.speed / 60, c.x, 0.000001)
end)

local World = require("src.game.world")
local WorldGen = require("src.game.world_gen")
local Walker = require("src.game.components.walker")

test("Session.new has an empty villager pool", function()
	assertEqual(0, #newSession().pools.villagers)
end)

test("Session.newGame spawns config.villagers.count idle villagers on open tiles near the storage facility", function()
	local ctx = Session.newGame(WorldGen.generate(Config, 1), Config, 1)
	local b = ctx.pools.buildings[1]
	local tile, radius = Config.tileSize, Config.villagers.spawnRadius
	local taken = {}
	assertEqual(20, Config.villagers.count)
	assertEqual(Config.villagers.count, #ctx.pools.villagers)
	for i, v in ipairs(ctx.pools.villagers) do
		local x, y = math.floor(v.x / tile), math.floor(v.y / tile)
		assertEqual(i, v.id)
		assertFalse(World.isBlocked(ctx.world, x, y), "villager " .. i .. " on a blocked tile")
		assertEqual(nil, World.portAt(ctx.world, x, y), "villager " .. i .. " on a port tile")
		assertFalse(taken[x .. "," .. y], "two villagers on tile " .. x .. "," .. y)
		taken[x .. "," .. y] = true
		assertTrue(x >= b.tileX - radius and x < b.tileX + b.width + radius, "villager " .. i .. " too far east-west")
		assertTrue(y >= b.tileY - radius and y < b.tileY + b.depth + radius, "villager " .. i .. " too far north-south")
		assertTrue(Walker.idle(v.walker))
		assertTrue(v.mover.throughBuildings)
	end
end)

test("Session.newGame spawns the same villagers for the same seed", function()
	local a = Session.newGame(WorldGen.generate(Config, 3), Config, 3)
	local b = Session.newGame(WorldGen.generate(Config, 3), Config, 3)
	for i, v in ipairs(a.pools.villagers) do
		assertEqual(v.x, b.pools.villagers[i].x)
		assertEqual(v.y, b.pools.villagers[i].y)
	end
end)

test("Session.step walks a villager sent across the map to its target, through the facility", function()
	local ctx = Session.newGame(WorldGen.generate(Config, 1), Config, 1)
	local b = ctx.pools.buildings[1]
	local v = ctx.pools.villagers[1]
	local tile = Config.tileSize
	-- The facility's far side from the villager, so the straight line runs through it.
	local tx = b.tileX + b.width + 1
	local ty = b.tileY
	assertTrue(Walker.goTo(v, ctx, b.tileX - 2, b.tileY), "route to the west side")
	for _ = 1, 60 * 30 do
		Session.advance(ctx, 1 / 60)
	end
	assertTrue(Walker.goTo(v, ctx, tx, ty), "route to the east side")
	local crossed = false
	for _ = 1, 60 * 30 do
		Session.advance(ctx, 1 / 60)
		crossed = crossed or World.buildingAt(ctx.world, math.floor(v.x / tile), math.floor(v.y / tile)) == b
		if Walker.idle(v.walker) and v.animator.frame == 1 then
			break
		end
	end
	assertTrue(crossed, "expected the villager to walk through the footprint")
	assertNear((tx + 0.5) * tile, v.x)
	assertNear((ty + 0.5) * tile, v.y)
	assertEqual(1, v.animator.frame, "idle once there")
end)

test("a villager sent across a generated map walks around water and trees to its target", function()
	local ctx = Session.newGame(WorldGen.generate(Config, 1), Config, 1)
	local v = ctx.pools.villagers[1]
	local tile = Config.tileSize
	local tx, ty = 12, 12
	while World.isBlocked(ctx.world, tx, ty) do
		tx = tx + 1
	end
	assertTrue(Walker.goTo(v, ctx, tx, ty), "expected a route across the map")
	-- Free, it heads for the gather area once it arrives: check the arrival.
	for _ = 1, 60 * 60 do
		Session.advance(ctx, 1 / 60)
		local x, y = math.floor(v.x / tile), math.floor(v.y / tile)
		assertEqual("grass", World.terrainAt(ctx.world, x, y))
		assertEqual(nil, World.nodeAt(ctx.world, x, y))
		if Walker.idle(v.walker) then
			break
		end
	end
	assertNear((tx + 0.5) * tile, v.x)
	assertNear((ty + 0.5) * tile, v.y)
end)
