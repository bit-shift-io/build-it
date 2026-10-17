-- The seeded world under real LÖVE 12: terrain, and tree and rock nodes
-- drawn from the baked prop atlas, which is cached in the save directory.
-- Captures land in tests/screenshots/world_render_test/.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local StorageFacility = require("src.game.components.storage_facility")
local Config = require("src.game.config")
local World = require("src.game.world")
local WorldGen = require("src.game.world_gen")
local Projection = require("src.game.projection")
local Registry = require("src.game.props.registry")
local PropCache = require("src.app.bake.prop_cache")

-- A config whose prop cache lives in its own save-directory folder, so the
-- tests never touch the game's real cache.
local function configWithCacheDir(dir)
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.props = { variants = Config.props.variants, seed = Config.props.seed, cacheDir = dir }
	return config
end

local function clearDir(dir)
	for _, name in ipairs(love.filesystem.getDirectoryItems(dir)) do
		love.filesystem.remove(dir .. "/" .. name)
	end
end

local function exists(path)
	return love.filesystem.getInfo(path) ~= nil
end

local function keys(list)
	local out = {}
	for _, v in ipairs(list) do
		out[#out + 1] = v
	end
	table.sort(out)
	return table.concat(out, ",")
end

-- Every sprite of every kind at a scale: loads (or bakes) each atlas.
local function touchAll(cache, kinds, scale)
	for name, def in pairs(kinds) do
		for variant = 1, Config.props.variants do
			for stage = 1, def.stages do
				local sprite = PropCache.sprite(cache, name, variant, stage, scale)
				assertTrue(sprite.image ~= nil and sprite.quad ~= nil, "sprite for " .. name .. " " .. variant .. "/" .. stage)
			end
		end
	end
end

-- Capture needs a live context, which a real session provides.
GameHarness.startSession({ width = 40, height = 30 }, { real = true })

test("the first launch bakes each prop kind into the cache, a second launch only loads it", function()
	local config = configWithCacheDir("e2e_props_relaunch")
	clearDir(config.props.cacheDir)

	local first = PropCache.new(Registry.KINDS, config)
	touchAll(first, Registry.KINDS, 1)
	assertEqual("bush@1,rock@1,tree@1", keys(first.baked))
	assertTrue(exists(config.props.cacheDir .. "/tree_v" .. Registry.KINDS.tree.version .. "_x1.png"), "tree atlas cached")
	assertTrue(exists(config.props.cacheDir .. "/rock_v" .. Registry.KINDS.rock.version .. "_x1.png"), "rock atlas cached")

	local second = PropCache.new(Registry.KINDS, config)
	touchAll(second, Registry.KINDS, 1)
	assertEqual("", keys(second.baked), "expected the second launch to bake nothing")
	Capture.captureTexture("tree_atlas_x1", PropCache.sprite(second, "tree", 1, 1, 1).image)
	Capture.captureTexture("rock_atlas_x1", PropCache.sprite(second, "rock", 1, 1, 1).image)
end)

test("bumping a generator version rebakes that kind only", function()
	local config = configWithCacheDir("e2e_props_version")
	clearDir(config.props.cacheDir)
	touchAll(PropCache.new(Registry.KINDS, config), Registry.KINDS, 1)

	local bumped = { rock = Registry.KINDS.rock, tree = {} }
	for k, v in pairs(Registry.KINDS.tree) do
		bumped.tree[k] = v
	end
	bumped.tree.version = Registry.KINDS.tree.version + 1

	local cache = PropCache.new(bumped, config)
	touchAll(cache, bumped, 1)
	assertEqual("tree@1", keys(cache.baked))
	assertTrue(exists(config.props.cacheDir .. "/tree_v" .. bumped.tree.version .. "_x1.png"), "new tree atlas cached")
	assertFalse(exists(config.props.cacheDir .. "/tree_v" .. Registry.KINDS.tree.version .. "_x1.png"), "stale tree atlas removed")
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

local function firstNode(world, kind)
	for _, n in ipairs(world.nodes) do
		if n.kind == kind then
			return n
		end
	end
end

-- Sprites stand up to 2 tiles tall, so a probed tile also needs the two
-- tiles south of it clear of nodes to show its own ground.
local SPRITE_REACH = 2

-- A water tile with water on the tiles south of it.
local function firstWater(world)
	for y = 0, world.height - 1 - SPRITE_REACH do
		for x = 0, world.width - 1 do
			local ok = true
			for dy = 0, SPRITE_REACH do
				ok = ok and World.terrainAt(world, x, y + dy) == "water"
			end
			if ok then
				return x, y
			end
		end
	end
end

local GRASS_SEARCH = 3 -- tiles

-- An open grass tile near (x, y) with open tiles south of it.
local function grassNear(world, x, y)
	for dy = -GRASS_SEARCH, GRASS_SEARCH do
		for dx = -GRASS_SEARCH, GRASS_SEARCH do
			local ok = true
			for oy = 0, SPRITE_REACH do
				ok = ok and not World.isBlocked(world, x + dx, y + dy + oy)
			end
			if ok then
				return x + dx, y + dy
			end
		end
	end
end

test("a seeded world draws water, trees and rocks, and leaves its prop cache behind", function()
	local config = configWithCacheDir("e2e_props_world")
	clearDir(config.props.cacheDir)
	local world = WorldGen.generate(config, 1)
	local game = GameHarness.startSession(world, { real = true, config = config, seed = 1 })
	local p = Projection.new(config)
	local w, h = love.graphics.getDimensions()
	game.camera.zoom = 2

	-- Point the camera at a tile centre and read the screen pixel there.
	local function look(tx, ty)
		local sx, sy = Projection.worldToScreen(p, tx + 0.5, ty + 0.5, 0)
		game.camera.x, game.camera.y = sx, sy
		local pixels = renderFrame(game)
		return pixels:getPixel(math.floor(w / 2), math.floor(h / 2))
	end

	local wx, wy = firstWater(world)
	local r, g, b = look(wx, wy)
	assertTrue(b > r and b > g, string.format("expected water blue at %d,%d, got %.2f %.2f %.2f", wx, wy, r, g, b))

	-- South-east of the centre: clear of the character.
	local gx, gy = grassNear(world, world.width / 2 + 4, world.height / 2 + 4)
	local gr, gg, gb = look(gx, gy)
	assertTrue(gg > gr and gg > gb, "expected grass green")

	-- A node's tile centre shows its sprite, never the bare grass colour.
	for _, kind in ipairs({ "tree", "rock" }) do
		local n = firstNode(world, kind)
		local nr, ng, nb = look(n.tileX, n.tileY)
		local same = math.abs(nr - gr) + math.abs(ng - gg) + math.abs(nb - gb) < 0.02
		assertFalse(same, string.format("expected a %s drawn on tile %d,%d", kind, n.tileX, n.tileY))
		Capture.capture("seed1_" .. kind .. "_region")
	end

	game.camera.zoom = 1
	look(world.width / 2, world.height / 2)
	Capture.capture("seed1_centre_zoom1")

	for _, kind in ipairs({ "tree", "rock" }) do
		local path = config.props.cacheDir .. "/" .. kind .. "_v" .. Registry.KINDS[kind].version .. "_x2.png"
		assertTrue(exists(path), "expected " .. path .. " cached after the first run")
	end
end)

test("a storage facility shows its fill label over the footprint", function()
	local config = configWithCacheDir("e2e_props_world")
	local world = WorldGen.generate(config, 1)
	local game = GameHarness.startSession(world, { real = true, config = config, seed = 1, storage = { plank = 2 } })
	local b = game.ctx.pools.buildings[1]
	local fill = StorageFacility.fill(b)
	assertTrue(fill ~= nil, "expected the starter facility to have capacity")
	local p = Projection.new(config)
	game.camera.zoom = 2
	game.camera.x, game.camera.y = Projection.worldToScreen(p, b.tileX + b.width / 2, b.tileY + b.depth / 2, 0)
	renderFrame(game)
	Capture.capture("storage_fill_label")
end)
