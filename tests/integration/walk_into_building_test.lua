-- The player walks into a finished building through its doorway, around
-- inside, and is stopped by its walls (docs/CONTEXT.md "Walk grid",
-- "Doorway"; ADR 0008). Driven through the real input path: the picker
-- places the design, WASD walks the character.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local DesignStore = require("src.app.design_store")
local Designs = require("tests.support.designs")

local TILE = Config.tileSize
local STUD = TILE / Config.walk.cellsPerTile

-- A 2x2 tile hut: walls 0.125 tiles thick (one stud) and a tile tall round
-- a floor, a 1-tile doorway in the south wall at x 0.5..1.5, and a bed.
local HUT = Designs.floor(
	2,
	2,
	"box{ size = { 2, 0.125, 1 } }",
	"box{ size = { 0.125, 2, 1 } }",
	"box{ size = { 0.125, 2, 1 }, transform = { move = { 1.875, 0, 0 } } }",
	"box{ size = { 0.5, 0.125, 1 }, transform = { move = { 0, 1.875, 0 } } }",
	"box{ size = { 0.5, 0.125, 1 }, transform = { move = { 1.5, 1.875, 0 } } }",
	Designs.ability("bed", 0.625, 0.625)
)

-- 20x20 world, character at its centre (px 320, 320), plenty of planks
-- in storage for the walls, HUT built facing N
-- on tiles 9..10 x 7..8: its doorway spans px 304..336, right above the
-- character.
local function launch()
	_G.love = LoveMock.new()
	assert(DesignStore.write(Config.designs, "designs", "walk_in", HUT))
	local world = World.new(20, 20)
	local game = GameHarness.startSession(world, { storage = { plank = 500 } })
	local c = game.ctx.pools.characters[1]
	Fake.pickDesign(game, "walk_in")
	-- The screen pixel over the footprint's middle, tile (10, 8)'s corner,
	-- camera on the character at zoom 1 in the mock's 1280x720 window.
	local sx, sy = 640 + (10 * TILE - c.x), 360 + (8 * TILE - c.y)
	game:mousemoved(sx, sy, 0, 0)
	Fake.click(game, 1, sx, sy)
	GameHarness.completeSites(game)
	local b = assert(World.buildingAt(world, 9, 7), "the hut is built")
	assert(b.tileX == 9 and b.tileY == 7 and b.functionBricks, "the hut is a building on tiles 9..10 x 7..8")
	return game, Fake.FakeInput.new(), c
end

test("the player walks in through the doorway and stops at the far wall", function()
	local game, input, c = launch()
	assertEqual(320, c.x)

	Fake.holdFor(game, input, "w", 1)

	assertEqual(320, c.x, "walked straight through the doorway")
	assertEqual(7 * TILE + STUD + c.size / 2, c.y, "stops flush against the north wall, inside")
end)

test("inside, the player walks around and the side wall stops it", function()
	local game, input, c = launch()
	Fake.holdFor(game, input, "w", 1)

	Fake.holdFor(game, input, "d", 1)

	assertEqual(11 * TILE - STUD - c.size / 2, c.x, "stops flush against the east wall, inside")
end)

test("the south wall beside the doorway stops the player outside", function()
	local game, input, c = launch()
	Fake.holdFor(game, input, "d", 0.15) -- about 24 px east: under the south wall east of the doorway

	Fake.holdFor(game, input, "w", 1)

	assertEqual(9 * TILE + c.size / 2, c.y,"stops flush against the south wall, outside")
end)
