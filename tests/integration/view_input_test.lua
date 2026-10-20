-- Input and picking in an isometric view, through the real input path:
-- WASD moves on screen, and the pointer resolves to the tile drawn under it.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local Projection = require("src.game.projection")
local WorldScreen = require("src.app.screens.world")

local TILE = Config.tileSize
local VIEWS = { "iso2to1", "iso" }

-- A 20x20 world shown in `view`; returns game, input, player, projection.
local function start(view)
	_G.love = LoveMock.new()
	local game = GameHarness.startSession(World.new(20, 20))
	game.flow.settings.view = view
	game.flow.world = WorldScreen.new(game.ctx, game.flow.library, view)
	return game, Fake.FakeInput.new(), game.ctx.pools.characters[1], Projection.new(Config, 1, Config.views[view])
end

local function screenPos(p, c)
	return Projection.worldToScreen(p, c.x / TILE, c.y / TILE, 0)
end

-- The window pixel at which world point (tx, ty) is drawn.
local function windowPos(game, p, tx, ty)
	local sx, sy = Projection.worldToScreen(p, tx, ty, 0)
	local cam = game.flow.world.camera
	return 1280 / 2 + (sx - cam.x) * cam.zoom, 720 / 2 + (sy - cam.y) * cam.zoom
end

for _, view in ipairs(VIEWS) do
	local DIRS = { w = { 0, -1 }, s = { 0, 1 }, a = { -1, 0 }, d = { 1, 0 } }
	for key, dir in pairs(DIRS) do
		test(key .. " moves the player on screen in " .. view, function()
			local game, input, c, p = start(view)
			local x0, y0 = screenPos(p, c)
			Fake.holdFor(game, input, key, 0.5)
			local x1, y1 = screenPos(p, c)
			local moved = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
			assertTrue(moved > 1, "moved")
			assertNear(dir[1], (x1 - x0) / moved, 0.0001)
			assertNear(dir[2], (y1 - y0) / moved, 0.0001)
		end)
	end

	test("walking diagonally is no faster than straight in " .. view, function()
		local game, input, c = start(view)
		local x0, y0 = c.x, c.y
		Fake.holdFor(game, input, "w", 0.5)
		local straight = math.sqrt((c.x - x0) ^ 2 + (c.y - y0) ^ 2)
		x0, y0 = c.x, c.y
		input:press("s")
		Fake.holdFor(game, input, "d", 0.5)
		input:release("s")
		local diagonal = math.sqrt((c.x - x0) ^ 2 + (c.y - y0) ^ 2)
		assertNear(straight, diagonal, straight * 0.15)
		assertTrue(diagonal <= straight * 1.001, "diagonal not faster")
	end)

	test("the camera follows the player in " .. view, function()
		local game, input, c, p = start(view)
		Fake.holdFor(game, input, "d", 0.5)
		local sx, sy = screenPos(p, c)
		assertNear(sx, game.flow.world.camera.x, 0.001)
		assertNear(sy, game.flow.world.camera.y, 0.001)
	end)

	test("a held click on a drawn tile targets that tile in " .. view, function()
		local game, _, c, p = start(view)
		local tx, ty = math.floor(c.x / TILE) + 2, math.floor(c.y / TILE) + 1
		local wx, wy = windowPos(game, p, tx + 0.5, ty + 0.5)
		game:mousemoved(wx, wy, 0, 0)
		game:mousepressed(wx, wy, 1)
		Fake.runUntil(game, function()
			return game.ctx.intents[1].target ~= nil
		end, 3)
		assertEqual(tx, game.ctx.intents[1].target.x)
		assertEqual(ty, game.ctx.intents[1].target.y)
	end)
end
