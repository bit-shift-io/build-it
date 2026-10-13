-- Water and resource nodes block walking, through the real input path:
-- FakeInput holds a key, src/app/input.lua makes the intent, Session.step
-- moves the character until the blocked tile stops it.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")

local TILE = Config.tileSize
local HALF = Config.character.size / 2

-- A 10x10 world; the character spawns at its centre, on tile (5, 5).
local function startIn(world)
	_G.love = LoveMock.new()
	local game = GameHarness.startSession(world)
	return game, Fake.FakeInput.new(), game.ctx.pools.characters[1]
end

local function waterColumn(x)
	local world = World.new(10, 10)
	for y = 0, 9 do
		World.setTerrain(world, x, y, "water")
	end
	return world
end

test("walking east into water stops the character at the shore", function()
	local game, input, c = startIn(waterColumn(7))
	local startY = c.y

	Fake.holdFor(game, input, "d", 2)

	assertNear(7 * TILE - HALF, c.x, 0.0001)
	assertNear(startY, c.y)
end)

test("walking west and north into water stops the character at the shore", function()
	local world = World.new(10, 10)
	for i = 0, 9 do
		World.setTerrain(world, 2, i, "water")
		World.setTerrain(world, i, 1, "water")
	end
	local game, input, c = startIn(world)

	Fake.holdFor(game, input, "a", 2)
	Fake.holdFor(game, input, "w", 2)

	assertNear(3 * TILE + HALF, c.x, 0.0001)
	assertNear(2 * TILE + HALF, c.y, 0.0001)
end)

test("walking diagonally into a shore slides along it", function()
	local game, input, c = startIn(waterColumn(7))
	local startY = c.y

	input:press("d")
	input:press("s")
	require("tests.support.frame_stepper").step(game, 60)

	assertNear(7 * TILE - HALF, c.x, 0.0001)
	assertTrue(c.y > startY + 20, "expected the character to keep moving south")
end)

test("a resource node blocks its tile like water", function()
	local world = World.new(10, 10)
	World.addNode(world, { id = 1, kind = "rock", tileX = 5, tileY = 7, variant = 1, stage = 1, amount = 8 })
	local game, input, c = startIn(world)
	local startX = c.x

	Fake.holdFor(game, input, "s", 2)

	assertNear(7 * TILE - HALF, c.y, 0.0001)
	assertNear(startX, c.x)
end)
