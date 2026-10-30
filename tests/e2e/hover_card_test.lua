-- The hover card under real LÖVE 12: the pointer over a villager's sprite
-- shows its name card, the pointer over bare ground shows nothing. Uses its
-- own save file, designs dir and prop cache, cleared first. Captures land in
-- tests/screenshots/hover_card_test/.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local FrameStepper = require("tests.support.frame_stepper")
local WorldScreen = require("src.app.screens.world")
local Config = require("src.game.config")

local function testConfig()
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.designs = { dir = "e2e_hover_designs", prefabDir = "e2e_hover_prefabs" }
	config.save = { file = "e2e_hover_world.save", seed = Config.save.seed }
	config.props = {}
	for k, v in pairs(Config.props) do
		config.props[k] = v
	end
	config.props.cacheDir = "e2e_hover_props"
	return config
end

local function clear(config)
	for _, dir in ipairs({ config.designs.dir, config.designs.prefabDir, config.props.cacheDir }) do
		for _, name in ipairs(love.filesystem.getDirectoryItems(dir)) do
			love.filesystem.remove(dir .. "/" .. name)
		end
	end
	love.filesystem.remove(config.save.file)
end

test("hovering a villager's sprite shows its card; bare ground shows none", function()
	local config = testConfig()
	clear(config)
	local game = GameHarness.launch({ real = true, config = config })
	FrameStepper.step(game, 1)
	game:keypressed("return")
	FrameStepper.step(game, 2)

	local screen = game.flow.world
	local cam = game.camera
	local w, h = love.graphics.getDimensions()
	-- Screen point over the middle of a villager's body, above its ground tile.
	local function over(r, lift)
		return w / 2 + (r.x - cam.x) * cam.zoom, h / 2 + (r.y - lift - cam.y) * cam.zoom
	end

	local v
	for _, candidate in ipairs(game.ctx.pools.villagers) do
		local sx, sy = over(candidate, 0)
		if sx > 0 and sx < w and sy > 0 and sy < h then
			v = candidate
			break
		end
	end
	assertTrue(v ~= nil, "a villager on screen")
	local sx, sy = over(v, 8)
	game:mousemoved(sx, sy, 0, 0)
	FrameStepper.step(game, 1)
	assertTrue(WorldScreen.hovered(screen) ~= nil, "a record under the pointer")
	Capture.capture("over_villager")

	-- A building whose reach covers the villager adds an aura line.
	local Aura = require("src.game.components.aura")
	for _, b in ipairs(game.ctx.pools.buildings) do
		b.aura = { walkSpeed = 0.05, harvestRate = 0 }
	end
	if Aura.at(game.ctx, v).walkSpeed > 0 then
		FrameStepper.step(game, 1)
		Capture.capture("over_villager_aura")
	end

	game:mousemoved(2, 2, 0, 0)
	FrameStepper.step(game, 1)
	assertEqual(nil, WorldScreen.hovered(screen))
	clear(config)
end)

test("hovering a building and a site shows reach outlines and the building card", function()
	local config = testConfig()
	clear(config)
	local game = GameHarness.launch({ real = true, config = config })
	FrameStepper.step(game, 1)
	game:keypressed("return")
	FrameStepper.step(game, 2)

	local Designs = require("tests.support.designs")
	local Placement = require("src.game.buildings.placement")
	local Storage = require("src.game.components.storage")
	local Projection = require("src.game.projection")
	local screen = game.flow.world
	local ctx = game.ctx
	local cam = game.camera
	local w, h = love.graphics.getDimensions()
	local player = screen.player
	local tx, ty = math.floor(player.x / config.tileSize) + 4, math.floor(player.y / config.tileSize) + 4

	local text = Designs.floor(2, 2, Designs.ability("saw", 0.5, 0.5))
	local building = Placement.build(ctx, Designs.request(text, "N", tx, ty, "Hover Saw"))
	local site = Placement.place(ctx, Designs.request(text, "N", tx + 6, ty, "Hover Site"))
	assertTrue(building ~= nil, "a building placed")

	local function hover(record)
		local p = Projection.new(config, 1, config.views[screen.view])
		local px, py = Projection.worldToScreen(p, record.tileX + record.width / 2, record.tileY + record.depth / 2, 0)
		game:mousemoved(w / 2 + (px - cam.x) * cam.zoom, h / 2 + (py - cam.y) * cam.zoom, 0, 0)
		FrameStepper.step(game, 1)
	end

	hover(building)
	assertEqual(building, WorldScreen.hoveredBuilding(screen))
	Capture.capture("over_building")

	if site then
		hover(site)
		assertEqual(site, WorldScreen.hoveredBuilding(screen))
		Capture.capture("over_site")
	end

	game:mousemoved(2, 2, 0, 0)
	FrameStepper.step(game, 1)
	assertEqual(nil, WorldScreen.hoveredBuilding(screen))
	clear(config)
end)
