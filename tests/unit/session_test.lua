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
