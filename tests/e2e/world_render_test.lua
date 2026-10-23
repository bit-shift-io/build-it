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

-- ---------------------------------------------------------------------------
-- Isometric views: the same world, drawn through each view's projection.

local WorldScreen = require("src.app.screens.world")
local Flow = require("src.app.flow")
local GhostRender = require("src.app.render.ghost")
local Camera = require("src.app.camera")
local Session = require("src.game.session")

local ISO_VIEWS = { "iso2to1", "iso" }

-- A session in `view`: the flow's setting picked up by a fresh world screen,
-- as Flow.begin builds it.
local function startInView(view, opts)
	local config = configWithCacheDir("e2e_props_world_views")
	local world = WorldGen.generate(config, 1)
	opts = opts or {}
	opts.real, opts.config, opts.seed = true, config, 1
	opts.storage = opts.storage or { plank = 2 }
	local game = GameHarness.startSession(world, opts)
	game.flow.settings.view = view
	game.flow.world = WorldScreen.new(game.ctx, function()
		return Flow.library(game.flow)
	end, game.flow.settings.view)
	return game, config, world
end

local function lookAt(game, config, view, tx, ty)
	local p = Projection.new(config, 1, config.views[view])
	game.camera.x, game.camera.y = Projection.worldToScreen(p, tx, ty, 0)
	return p
end

local function centrePixel(game)
	local w, h = love.graphics.getDimensions()
	return renderFrame(game):getPixel(math.floor(w / 2), math.floor(h / 2))
end

for _, view in ipairs(ISO_VIEWS) do
	test("the " .. view .. " world draws water, grass, a tree and a building at their projected pixels", function()
		local game, config, world = startInView(view)
		game.camera.zoom = 2

		local wx, wy = firstWater(world)
		lookAt(game, config, view, wx + 0.5, wy + 0.5)
		local r, g, b = centrePixel(game)
		assertTrue(b > r and b > g, string.format("expected water blue, got %.2f %.2f %.2f", r, g, b))

		local gx, gy = grassNear(world, world.width / 2 + 4, world.height / 2 + 4)
		lookAt(game, config, view, gx + 0.5, gy + 0.5)
		local gr, gg, gb = centrePixel(game)
		assertTrue(gg > gr and gg > gb, "expected grass green")

		local n = firstNode(world, "tree")
		lookAt(game, config, view, n.tileX + 0.5, n.tileY + 0.5)
		local nr, ng, nb = centrePixel(game)
		local same = math.abs(nr - gr) + math.abs(ng - gg) + math.abs(nb - gb) < 0.02
		assertFalse(same, "expected a tree drawn at its projected tile")
		Capture.capture(view .. "_tree_region")

		-- The building's footprint centre, a little up its sprite.
		local bld = game.ctx.pools.buildings[1]
		lookAt(game, config, view, bld.tileX + bld.width / 2, bld.tileY + bld.depth / 2)
		local br, bg, bb = centrePixel(game)
		assertFalse(math.abs(br - gr) + math.abs(bg - gg) + math.abs(bb - gb) < 0.02, "expected the building drawn at its projected footprint")
		Capture.capture(view .. "_building_region")

		game.camera.zoom = 1
		lookAt(game, config, view, world.width / 2, world.height / 2)
		Capture.capture(view .. "_centre_zoom1")
		for _, kind in ipairs({ "tree", "rock" }) do
			assertTrue(exists(config.props.cacheDir .. "/" .. kind .. "_v" .. Registry.KINDS[kind].version .. "_x2_" .. view .. ".png"), "iso props cache under the view's own name")
		end
	end)
end

-- Rendered pixels in the box (x0, y0)-(x1, y1) of two frames that differ.
local function differing(a, b, x0, y0, x1, y1, mask)
	local count = 0
	for y = y0, y1 do
		for x = x0, x1 do
			if not mask or mask(x, y) then
				local ar, ag, ab = a:getPixel(x, y)
				local br, bg, bb = b:getPixel(x, y)
				if math.abs(ar - br) + math.abs(ag - bg) + math.abs(ab - bb) > 0.02 then
					count = count + 1
				end
			end
		end
	end
	return count
end

for _, view in ipairs(ISO_VIEWS) do
	test("in " .. view .. " a villager south-east of a building draws over it, one north-west behind it", function()
		local game, config = startInView(view)
		local ctx = game.ctx
		local w, h = love.graphics.getDimensions()
		local b = ctx.pools.buildings[1]
		-- A bare scene: the building, one villager, nothing else.
		ctx.pools.villagers, ctx.pools.nodes, ctx.pools.animals = {}, {}, {}
		ctx.pools.characters[1].x, ctx.pools.characters[1].y = 2 * config.tileSize, 2 * config.tileSize
		lookAt(game, config, view, b.tileX + b.width / 2, b.tileY + b.depth / 2)
		game.camera.zoom = 1

		local function frameWith(tx, ty)
			ctx.pools.villagers = {}
			if tx then
				table.insert(ctx.pools.villagers, Session.newVillager(1, (tx + 0.5) * config.tileSize, (ty + 0.5) * config.tileSize, config))
			end
			return renderFrame(game)
		end

		local alone = frameWith(nil)
		-- The building's own sprite pixels (not its port markers, which a
		-- villager legitimately covers), by the sprite's alpha.
		local BuildingsRender = require("src.app.render.buildings")
		local sprite = BuildingsRender.sprite(config, b.blueprint, b.facing, 1, view)
		local alpha = love.graphics.readbackTexture(sprite.image)
		local p = Projection.new(config, 1, config.views[view])
		local left, top = Projection.placeSprite(p, sprite.frame, b.tileX, b.tileY)
		local function onBuilding(x, y)
			local sx = math.floor(x - w / 2 + game.camera.x - left)
			local sy = math.floor(y - h / 2 + game.camera.y - top)
			if sx < 0 or sy < 0 or sx >= sprite.frame.width or sy >= sprite.frame.height then
				return false
			end
			return select(4, alpha:getPixel(sx, sy)) > 0.99
		end

		-- Both stand partly inside the footprint, a little off its centre.
		local front = frameWith(b.tileX + 0.4, b.tileY + 0.4)
		local back = frameWith(b.tileX - 0.4, b.tileY - 0.4)
		Capture.capture(view .. "_villager_behind")
		assertTrue(differing(alone, front, 0, 0, w - 1, h - 1, onBuilding) > 0, "expected the south-east villager over the building")
		assertEqual(0, differing(alone, back, 0, 0, w - 1, h - 1, onBuilding), "expected the north-west villager hidden by the building")
	end)
end

test("a ghost's outline sits on its footprint's tiles in an iso view", function()
	for _, view in ipairs(ISO_VIEWS) do
		local game, config = startInView(view)
		local ctx = game.ctx
		local w, h = love.graphics.getDimensions()
		local b = ctx.pools.buildings[1]
		local req = { design = b.design, blueprint = b.blueprint, facing = b.facing, tileX = 10, tileY = 10 }
		local width, depth = b.width, b.depth
		local p = lookAt(game, config, view, req.tileX + width, req.tileY + depth / 2)
		game.camera.zoom = 1

		local canvas = love.graphics.newCanvas(w, h, { dpiscale = 1 })
		love.graphics.push("all")
		love.graphics.setCanvas(canvas)
		love.graphics.clear(0, 0, 0, 1)
		Camera.attach(game.camera, w, h)
		GhostRender.draw(ctx, { request = req, ok = true }, 1, view)
		Camera.detach()
		love.graphics.pop()
		local pixels = love.graphics.readbackTexture(canvas)
		-- The south-east edge's midpoint is on the view centre: outline green.
		local r, g, bl = pixels:getPixel(math.floor(w / 2), math.floor(h / 2))
		assertTrue(g > 0.8 and g > r and g > bl, view .. ": expected the valid outline at the footprint's south-east edge midpoint")
		assertEqual(0, ({ pixels:getPixel(1, 1) })[1], "far from the ghost stays clear")
		assertTrue(p ~= nil)
	end
end)

test("a storage facility's fill label and ports draw in iso views", function()
	for _, view in ipairs(ISO_VIEWS) do
		local game, config = startInView(view, { storage = { plank = 2 } })
		local b = game.ctx.pools.buildings[1]
		game.camera.zoom = 2
		lookAt(game, config, view, b.tileX + b.width / 2, b.tileY + b.depth / 2)
		renderFrame(game)
		Capture.capture(view .. "_storage_fill_label")
	end
end)
