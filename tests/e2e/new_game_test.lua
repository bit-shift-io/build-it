-- A new game under real LÖVE 12: the starting storage facility at the
-- world centre holding the stockpile, 20 villagers around it, and
-- villagers that set off on their own. Uses its own save file, designs
-- dir and prop cache, cleared first. Captures land in
-- tests/screenshots/new_game_test/.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local FrameStepper = require("tests.support.frame_stepper")
local Config = require("src.game.config")
local Starter = require("src.game.designs.starter")
local StorageFacility = require("src.game.components.storage_facility")

local function testConfig()
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.designs = { dir = "e2e_newgame_designs", prefabDir = "e2e_newgame_prefabs" }
	config.save = { file = "e2e_newgame_world.save", seed = Config.save.seed }
	config.props = {}
	for k, v in pairs(Config.props) do
		config.props[k] = v
	end
	config.props.cacheDir = "e2e_newgame_props"
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

test("a new game shows the storage facility with the stockpile and 20 villagers around it", function()
	local config = testConfig()
	clear(config)
	local game = GameHarness.launch({ real = true, config = config })
	FrameStepper.step(game, 1)
	game:keypressed("return")
	assertEqual("world", game.flow.screen)

	local ctx = game.ctx
	local facility = ctx.pools.buildings[1]
	assertEqual(Starter.NAME, facility.design)
	local totals = StorageFacility.totals(ctx)
	assertEqual(50, totals.plank)
	assertEqual(50, totals.stone)
	assertEqual(config.villagers.count, #ctx.pools.villagers)

	FrameStepper.step(game, 2)
	Capture.capture("start")

	-- Zoomed out a little, a few seconds in.
	game.camera.zoom = 1.5
	FrameStepper.step(game, 180)
	Capture.capture("after_3s")
	clear(config)
end)
