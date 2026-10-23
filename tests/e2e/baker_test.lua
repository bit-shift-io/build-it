-- The baker under real LÖVE 12: canvas + depth buffer + block shader render
-- a block model through the shared projection into a transparent sprite.
-- Sprites are captured to tests/screenshots/baker_test/ for eyeballing.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local Config = require("src.game.config")
local Model = require("src.game.blocks.model")
local Baker = require("src.app.bake.baker")
local Starter = require("src.game.designs.starter")
local Builtins = require("src.game.designs.builtins")
local Placement = require("src.game.buildings.placement")
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

-- The starting storage facility (src/game/designs/starter.lua), compiled
-- from the built-in Lua design into the blueprint DesignCache bakes.
local function houseBlueprint()
	local library = assert(Builtins.load(function(path)
		return love.filesystem.read(path)
	end))
	return Starter.blueprint(library, Config)
end

test("the starter house bakes from its triangle mesh in all 4 facings, footprint turning with the facing", function()
	local house = houseBlueprint()
	local wantWidth = { N = house.width, E = house.depth, S = house.width, W = house.depth }
	for _, facing in ipairs(Model.FACINGS) do
		local sprite = Baker.bakeMesh(house.mesh, house.width, house.depth, facing, Config, 2)
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

-- Ground and grid are green-dominant; the house's tan wall, brown door
-- and red roof are not.
local function isHouse(pixels, x, y)
	local r, g, _, a = pixels:getPixel(math.floor(x), math.floor(y))
	return a == 1 and r > g
end

local function isGround(pixels, x, y)
	local r, g = pixels:getPixel(math.floor(x), math.floor(y))
	return g > r + 0.05
end

test("the starter house draws with its footprint exactly on its tiles at every zoom", function()
	local world = { width = 40, height = 30 }
	local game = GameHarness.startSession(world, { real = true })
	local house = houseBlueprint()
	local place = { design = Starter.NAME, blueprint = house, facing = "N", tileX = 10, tileY = 6 }
	Placement.build(game.ctx, place)
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

-- A tall red column at the north-west with a low blue cube in front of it
-- (nearer the viewer in every view). Where the cube's top face draws, the
-- column's walls are behind it on screen; a correct depth test shows blue.
local RED, BLUE = { 0.9, 0.1, 0.1 }, { 0.1, 0.1, 0.9 }

local function occludingModel(nearX)
	local m = Model.new(1, 2, 2)
	for z = 0, 2 do
		Model.addCell(m, { x = 0, y = 0, z = z, color = RED })
	end
	Model.addCell(m, { x = nearX, y = 1, z = 0, color = BLUE })
	return m
end

local VIEW_NAMES = { "topdown", "iso2to1", "iso" }

for _, name in ipairs(VIEW_NAMES) do
	test("bakes through the " .. name .. " view: frame matches the projection, nearer face covers farther", function()
		local view = Config.views[name]
		local nearX = name == "topdown" and 0 or 1
		local model = occludingModel(nearX)
		local sprite = Baker.bake(model, "N", Config, 2, view)
		Capture.captureTexture("occluding_" .. name .. "_x2", sprite.image)

		local p = Projection.new(Config, 2, view)
		local frame = Projection.spriteFrame(p, { minX = 0, minY = 0, minZ = 0, maxX = nearX + 1, maxY = 2, maxZ = 3 })
		assertEqual(frame.width, sprite.image:getWidth(), "sprite width")
		assertEqual(frame.height, sprite.image:getHeight(), "sprite height")
		assertEqual(frame.anchorX, sprite.frame.anchorX, "anchor x")
		assertEqual(frame.anchorY, sprite.frame.anchorY, "anchor y")

		local pixels = love.graphics.readbackTexture(sprite.image)
		local px, py = Projection.modelToSprite(p, sprite.frame, nearX + 0.5, 1.5, 1)
		local r, _, b, a = pixels:getPixel(math.floor(px), math.floor(py))
		assertEqual(1, a, "expected an opaque near top face")
		assertTrue(b > r, string.format("expected the near blue cube over the red column (r %.2f b %.2f)", r, b))

		-- The column's own top, the farthest-highest point, is not clipped away.
		local tx, ty = Projection.modelToSprite(p, sprite.frame, 0.5, 0.5, 3)
		local cr, _, cb, ca = pixels:getPixel(math.floor(tx), math.floor(ty) + 1)
		assertEqual(1, ca, "expected the column top to be present")
		assertTrue(cr > cb, "expected the column top red")
	end)
end

test("the default view bakes the same pixels as passing topdown explicitly", function()
	local model = stepModel()
	local a = love.graphics.readbackTexture(Baker.bake(model, "N", Config, 2).image)
	local b = love.graphics.readbackTexture(Baker.bake(model, "N", Config, 2, Config.views.topdown).image)
	assertEqual(a:getString(), b:getString(), "pixels differ")
end)

local DesignCache = require("src.app.bake.design_cache")
local PropCache = require("src.app.bake.prop_cache")

test("design sprites of two views coexist in memory, each baked once", function()
	local blueprint = houseBlueprint()
	local cache = DesignCache.new(Config)
	local top = DesignCache.sprite(cache, blueprint, "N", 1)
	local iso = DesignCache.sprite(cache, blueprint, "N", 1, "iso")
	assertTrue(top ~= iso and top.frame.height ~= iso.frame.height, "views bake different sprites")
	assertEqual(2, #cache.baked, "one bake per view")
	assertTrue(top == DesignCache.sprite(cache, blueprint, "N", 1, "topdown"), "topdown reused")
	assertTrue(iso == DesignCache.sprite(cache, blueprint, "N", 1, "iso"), "iso reused")
	assertEqual(2, #cache.baked, "no rebake when switching back")
end)

local function exists(path)
	return love.filesystem.getInfo(path) ~= nil
end

local function clearDir(dir)
	for _, name in ipairs(love.filesystem.getDirectoryItems(dir)) do
		love.filesystem.remove(dir .. "/" .. name)
	end
end

test("prop atlases of two views coexist on disk; a version bump removes only that view's stale files", function()
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.props = { variants = Config.props.variants, seed = Config.props.seed, cacheDir = "e2e_baker_views" }
	clearDir(config.props.cacheDir)
	local Registry = require("src.game.props.registry")
	local def = Registry.KINDS.rock
	local dir = config.props.cacheDir

	local cache = PropCache.new({ rock = def }, config)
	local top = PropCache.sprite(cache, "rock", 1, 1, 1)
	local iso = PropCache.sprite(cache, "rock", 1, 1, 1, "iso")
	assertEqual("rock@1,rock@1@iso", table.concat(cache.baked, ","))
	assertTrue(top.frame.width ~= iso.frame.width or top.frame.height ~= iso.frame.height, "views bake different sprites")
	local topName = "rock_v" .. def.version .. "_x1"
	assertTrue(exists(dir .. "/" .. topName .. ".png"), "topdown file name unchanged")
	assertTrue(exists(dir .. "/" .. topName .. "_iso.png"), "iso file has a view suffix")
	assertTrue(exists(dir .. "/" .. topName .. "_iso.txt"), "iso entries written")

	-- A later launch loads both from disk and bakes nothing.
	local again = PropCache.new({ rock = def }, config)
	local reloaded = PropCache.sprite(again, "rock", 1, 1, 1, "iso")
	PropCache.sprite(again, "rock", 1, 1, 1)
	assertEqual("", table.concat(again.baked, ","), "expected both atlases to load from disk")
	assertEqual(iso.frame.width, reloaded.frame.width)
	assertEqual(iso.frame.height, reloaded.frame.height)

	-- Bumping the version for iso removes only the stale iso files.
	local bumped = {}
	for k, v in pairs(def) do
		bumped[k] = v
	end
	bumped.version = def.version + 1
	local third = PropCache.new({ rock = bumped }, config)
	PropCache.sprite(third, "rock", 1, 1, 1, "iso")
	assertTrue(exists(dir .. "/rock_v" .. bumped.version .. "_x1_iso.png"), "new iso atlas cached")
	assertFalse(exists(dir .. "/" .. topName .. "_iso.png"), "stale iso atlas removed")
	assertTrue(exists(dir .. "/" .. topName .. ".png"), "topdown atlas untouched")
	clearDir(dir)
end)
