-- One scene (a building, trees, villagers, deer and a placement ghost) drawn
-- through each view, captured side by side for visual review in
-- tests/screenshots/view_render_test/, with the building's and a tree's
-- anchor pixels checked against Projection per view.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local Config = require("src.game.config")
local WorldGen = require("src.game.world_gen")
local Projection = require("src.game.projection")
local Session = require("src.game.session")
local AnimalSystem = require("src.game.systems.animal_system")
local WorldScreen = require("src.app.screens.world")
local Flow = require("src.app.flow")
local GhostRender = require("src.app.render.ghost")
local Camera = require("src.app.camera")

local VIEWS = { "topdown", "iso2to1", "iso" }

GameHarness.startSession({ width = 40, height = 30 }, { real = true })

local function configWithCacheDir(dir)
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.props = { variants = Config.props.variants, seed = Config.props.seed, cacheDir = dir }
	return config
end

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

-- Bounding box { x0, y0, x1, y1 } of the pixels that differ between two
-- frames, or nil when they are identical.
local function diffBox(a, b)
	local w, h = love.graphics.getDimensions()
	local box
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local ar, ag, ab = a:getPixel(x, y)
			local br, bg, bb = b:getPixel(x, y)
			if math.abs(ar - br) + math.abs(ag - bg) + math.abs(ab - bb) > 0.02 then
				box = box or { x0 = x, y0 = y, x1 = x, y1 = y }
				box.x0, box.y0 = math.min(box.x0, x), math.min(box.y0, y)
				box.x1, box.y1 = math.max(box.x1, x), math.max(box.y1, y)
			end
		end
	end
	return box
end

-- The scene around a storage facility on the world's centre: a tree to its east, two
-- villagers, a deer, and a ghost of the same design to its south. The ghost
-- is drawn by wrapping the game's draw, so captures include it.
local function buildScene(view)
	local config = configWithCacheDir("e2e_props_view_render")
	local world = WorldGen.generate(config, 1)
	local game = GameHarness.startSession(world, { real = true, config = config, seed = 1 })
	-- On the world's centre, which worldgen keeps clear grass.
	GameHarness.addStorage(game.ctx, { plank = 2 }, world.width / 2, world.height / 2)
	game.flow.settings.view = view
	game.flow.world = WorldScreen.new(game.ctx, function()
		return Flow.library(game.flow)
	end, view)
	local ctx = game.ctx
	local tile = config.tileSize
	local b = ctx.pools.buildings[1]

	ctx.pools.nodes = {}
	local tree = { kind = "tree", tileX = b.tileX + b.width + 3, tileY = b.tileY, variant = 1, stage = 1, amount = 1 }
	local tree2 = { kind = "tree", tileX = b.tileX + b.width + 2, tileY = b.tileY + 2, variant = 2, stage = 1, amount = 1 }
	table.insert(ctx.pools.nodes, tree)
	table.insert(ctx.pools.nodes, tree2)

	ctx.pools.villagers = {
		Session.newVillager(1, (b.tileX - 1.5) * tile, (b.tileY + 0.5) * tile, config),
		Session.newVillager(2, (b.tileX + b.width + 0.5) * tile, (b.tileY + b.depth + 0.5) * tile, config),
	}
	ctx.pools.animals = {}
	local herd = AnimalSystem.addHerd(ctx, b.tileX - 4, b.tileY + 3, 1)
	AnimalSystem.spawn(ctx, herd, b.tileX - 4, b.tileY + 3)

	local req = { design = b.design, blueprint = b.blueprint, facing = b.facing, tileX = b.tileX, tileY = b.tileY + b.depth + 2 }
	local plainDraw = game.draw
	game.draw = function(self)
		plainDraw(self)
		local w, h = love.graphics.getDimensions()
		Camera.attach(self.camera, w, h)
		GhostRender.draw(ctx, { request = req, ok = true }, self.camera.zoom, view)
		Camera.detach()
	end

	local p = Projection.new(config, 1, config.views[view])
	game.camera.x, game.camera.y = Projection.worldToScreen(p, b.tileX + b.width / 2 + 1, b.tileY + b.depth / 2 + 1, 0)
	game.camera.zoom = 2
	return game, config, p, b, tree
end

for _, view in ipairs(VIEWS) do
	test("the " .. view .. " scene is captured with its building and tree at their projected pixels", function()
		local game, config, p, b, tree = buildScene(view)
		local w, h = love.graphics.getDimensions()
		Capture.capture("scene_" .. view)

		-- Anchor check at zoom 1: removing a thing changes pixels around
		-- where Projection puts it.
		game.camera.zoom = 1
		local function pixelOf(tx, ty)
			local sx, sy = Projection.worldToScreen(p, tx, ty, 0)
			return w / 2 + sx - game.camera.x, h / 2 + sy - game.camera.y
		end
		-- A sprite's lowest row can sit a pixel above its ground anchor.
		local SLACK = 2
		local function inBox(box, px, py)
			return box ~= nil and px >= box.x0 - SLACK and px <= box.x1 + SLACK and py >= box.y0 - SLACK and py <= box.y1 + SLACK
		end

		local with = renderFrame(game)
		table.remove(game.ctx.pools.nodes, 1)
		local treeBox = diffBox(with, renderFrame(game))
		local tx, ty = pixelOf(tree.tileX + 0.5, tree.tileY + 0.5)
		assertTrue(inBox(treeBox, tx, ty), view .. ": expected the tree's changed pixels to cover its projected tile centre")

		local bx, by = pixelOf(b.tileX + b.width / 2, b.tileY + b.depth / 2)
		local building = table.remove(game.ctx.pools.buildings, 1)
		local without = renderFrame(game)
		table.insert(game.ctx.pools.buildings, 1, building)
		local buildingBox = diffBox(renderFrame(game), without)
		assertTrue(inBox(buildingBox, bx, by), view .. ": expected the building's changed pixels to cover its projected footprint centre")
	end)
end
