-- The baker under real LÖVE 12: canvas + depth buffer + block shader render
-- a block model through the shared projection into a transparent sprite.
-- Sprites are captured to tests/screenshots/baker_test/ for eyeballing.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local Config = require("src.game.config")
local Model = require("src.game.blocks.model")
local Baker = require("src.app.bake.baker")
local TestHouse = require("src.game.blocks.test_house")
local Projection = require("src.game.projection")

local GREY = { 0.8, 0.8, 0.8 }

-- One tile per cell: a cube with a two-cube column east of it.
--   column top    [ ][#]
--   cube + column [#][#]   (seen from the front)
local function stepModel()
	local m = Model.new(1, 2, 1)
	Model.addCell(m, { x = 0, y = 0, z = 0, color = GREY })
	Model.addCell(m, { x = 1, y = 0, z = 0, color = GREY })
	Model.addCell(m, { x = 1, y = 0, z = 1, color = GREY })
	return m
end

local function brightness(r, g, b)
	return r + g + b
end

-- Capture needs a live context, which a real session provides.
GameHarness.startSession({ width = 40, height = 30 }, { real = true })

test("bakes a known model to a projection-sized transparent sprite, top lit above side", function()
	local tile = Config.tileSize
	local k = Config.projection.heightScale
	local sprite = Baker.bake(stepModel(), "N", Config, 1)
	Capture.captureTexture("step_N_x1", sprite.image)

	assertEqual(2 * tile, sprite.image:getWidth())
	assertEqual((1 + 2 * k) * tile, sprite.image:getHeight())
	assertEqual(sprite.frame.width, sprite.image:getWidth())

	local pixels = love.graphics.readbackTexture(sprite.image)
	-- Above the lone cube, beside the column: empty.
	local _, _, _, emptyAlpha = pixels:getPixel(tile / 2, (k * tile) / 2)
	assertEqual(0, emptyAlpha, "expected a transparent background above the cube")

	-- The cube's top face spans sprite rows [k, 2k] tiles; its front face [2k, 2k + 1].
	local tr, tg, tb, ta = pixels:getPixel(tile / 2, (1.5 * k) * tile)
	local fr, fg, fb, fa = pixels:getPixel(tile / 2, (2 * k + 0.5) * tile)
	assertEqual(1, ta, "expected an opaque top face")
	assertEqual(1, fa, "expected an opaque front face")
	assertTrue(
		brightness(tr, tg, tb) > brightness(fr, fg, fb),
		string.format("expected the top (%.2f) brighter than the front (%.2f)", brightness(tr, tg, tb), brightness(fr, fg, fb))
	)
end)

test("bakes at whole scales: scale 2 doubles the sprite and its anchor", function()
	local one = Baker.bake(stepModel(), "N", Config, 1)
	local two = Baker.bake(stepModel(), "N", Config, 2)
	assertEqual(2 * one.image:getWidth(), two.image:getWidth())
	assertEqual(2 * one.image:getHeight(), two.image:getHeight())
	assertEqual(2 * one.frame.anchorY, two.frame.anchorY)
end)

test("the test house bakes in all 4 facings, footprint turning with the facing", function()
	local house = TestHouse.model()
	local wantWidth = { N = house.width, E = house.depth, S = house.width, W = house.depth }
	for _, facing in ipairs(Model.FACINGS) do
		local sprite = Baker.bake(house, facing, Config, 2)
		Capture.captureTexture("house_" .. facing .. "_x2", sprite.image)
		assertEqual(wantWidth[facing], sprite.width, "footprint width facing " .. facing)
		-- Walls stand flush on the footprint, so the sprite is exactly as wide.
		assertEqual(wantWidth[facing] * Config.tileSize * 2, sprite.image:getWidth(), "sprite width facing " .. facing)
	end
end)

-- Renders the game into a window-sized canvas at 1 px per unit and reads it back.
local function renderFrame(game)
	local w, h = love.graphics.getDimensions()
	local canvas = love.graphics.newCanvas(w, h, { dpiscale = 1 })
	love.graphics.push("all")
	love.graphics.setCanvas(canvas)
	love.graphics.clear(love.graphics.getBackgroundColor())
	game:draw()
	love.graphics.pop()
	return love.graphics.readbackTexture(canvas)
end

-- Ground and grid are green-dominant; the house's cream wall is red-dominant.
local function isHouse(pixels, x, y)
	local r, g, _, a = pixels:getPixel(math.floor(x), math.floor(y))
	return a == 1 and r > g + 0.05
end

local function isGround(pixels, x, y)
	local r, g = pixels:getPixel(math.floor(x), math.floor(y))
	return g > r + 0.05
end

test("the test house draws with its footprint exactly on its tiles at every zoom", function()
	local world = { width = 40, height = 30 }
	local game = GameHarness.startSession(world, { real = true })
	local place = TestHouse.placements(world, Config)[1]
	assertEqual("N", place.facing)
	local house = TestHouse.model()
	local p = Projection.new(Config)
	local w, h = love.graphics.getDimensions()

	local cx, cy = Projection.worldToScreen(p, place.tileX + house.width / 2, place.tileY + house.depth / 2, 0)
	game.camera.x, game.camera.y = cx, cy

	for _, zoom in ipairs({ 1, 1.5, 2.6, 4 }) do
		game.camera.zoom = zoom
		local pixels = renderFrame(game)
		local function toScreen(tx, ty)
			local sx, sy = Projection.worldToScreen(p, tx, ty, 0)
			return (sx - cx) * zoom + w / 2, (sy - cy) * zoom + h / 2
		end
		-- Just inside and just outside the footprint's south-west and south-east
		-- ground corners: the adjacent pixel at whole zooms, where sprites draw
		-- 1:1; clear of filtered edges otherwise. Outside also clears the grid
		-- line, which scales with zoom.
		local inset = zoom == math.floor(zoom) and 0.5 or 1.5
		local outset = inset + zoom / 2
		local swx, swy = toScreen(place.tileX, place.tileY + house.depth)
		local sex, sey = toScreen(place.tileX + house.width, place.tileY + house.depth)
		local label = string.format(" at zoom %.1f", zoom)
		assertTrue(isHouse(pixels, swx + inset, swy - inset), "house inside the south-west corner" .. label)
		assertTrue(isGround(pixels, swx - outset, swy + outset), "ground outside the south-west corner" .. label)
		assertTrue(isHouse(pixels, sex - inset, sey - inset), "house inside the south-east corner" .. label)
		assertTrue(isGround(pixels, sex + outset, sey + outset), "ground outside the south-east corner" .. label)
		Capture.capture(string.format("world_zoom_%.1f", zoom))
	end
end)
