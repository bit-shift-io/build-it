-- Deer under real LÖVE 12: a new world has deer, the camera over a herd
-- draws them (baking the deer atlas on the way), and they wander. Uses its
-- own save file, designs dir and prop cache, cleared first. Captures land in
-- tests/screenshots/deer_render_test/.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local FrameStepper = require("tests.support.frame_stepper")
local Config = require("src.game.config")

local function testConfig()
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.designs = { dir = "e2e_deer_designs", prefabDir = "e2e_deer_prefabs" }
	config.save = { file = "e2e_deer_world.save", seed = Config.save.seed }
	config.props = {}
	for k, v in pairs(Config.props) do
		config.props[k] = v
	end
	config.props.cacheDir = "e2e_deer_props"
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

test("a new world has deer; the camera beside a herd draws them wandering", function()
	local config = testConfig()
	clear(config)
	local game = GameHarness.launch({ real = true, config = config })
	FrameStepper.step(game, 1)
	game:keypressed("return")
	FrameStepper.step(game, 2)

	local animals = game.ctx.pools.animals
	assertTrue(#animals > 0, "expected deer in a new world")
	local deer = animals[1]
	-- The camera follows the player: stand it beside the deer.
	local player = game.ctx.pools.characters[1]
	player.x, player.y = deer.x - Config.tileSize, deer.y
	local x, y = deer.x, deer.y
	FrameStepper.step(game, 2)
	Capture.capture("deer_in_view")
	FrameStepper.step(game, 60 * 12)
	assertTrue(deer.x ~= x or deer.y ~= y, "expected the deer to wander")
	Capture.capture("deer_later")
	clear(config)
end)
