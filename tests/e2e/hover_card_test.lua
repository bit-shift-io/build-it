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
	config.designs = { dir = "e2e_hover_designs", maxNameLength = Config.designs.maxNameLength }
	config.save = { file = "e2e_hover_world.save", seed = Config.save.seed }
	config.props = {}
	for k, v in pairs(Config.props) do
		config.props[k] = v
	end
	config.props.cacheDir = "e2e_hover_props"
	return config
end

local function clear(config)
	for _, dir in ipairs({ config.designs.dir, config.props.cacheDir }) do
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

	game:mousemoved(2, 2, 0, 0)
	FrameStepper.step(game, 1)
	assertEqual(nil, WorldScreen.hovered(screen))
	clear(config)
end)
