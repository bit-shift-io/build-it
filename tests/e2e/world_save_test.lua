-- World save and load under real LÖVE 12: the title screen, and a saved
-- building whose design file is gone from the library still drawing from
-- the blueprint in the save. Uses its own save file and design folders,
-- cleared first. Captures land in tests/screenshots/world_save_test/.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local FrameStepper = require("tests.support.frame_stepper")
local Config = require("src.game.config")
local World = require("src.game.world")
local DesignStore = require("src.app.design_store")
local Placement = require("src.game.buildings.placement")
local Compile = require("src.game.buildings.compile")
local Flow = require("src.app.flow")
local BuildingsRender = require("src.app.render.buildings")
local Projection = require("src.game.projection")

local function testConfig()
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.designs = { dir = "e2e_save_designs", prefabDir = "e2e_save_prefabs" }
	config.save = { file = "e2e_world.save", seed = Config.save.seed }
	return config
end

local function clear(config)
	for _, dir in ipairs({ config.designs.dir, config.designs.prefabDir }) do
		for _, name in ipairs(love.filesystem.getDirectoryItems(dir)) do
			love.filesystem.remove(dir .. "/" .. name)
		end
	end
	love.filesystem.remove(config.save.file)
end

-- A 2x1 tile woodcutter: a floor, a saw, a tower and an output port.
local WOODCUTTER = [[
return group{ id = "root", name = "Woodcutter",
	box{ id = "floor", size = { 2, 1, 0.125 } },
	box{ id = "tower", size = { 0.5, 0.5, 1.25 }, transform = { move = { 1.5, 0, 0 } } },
	prefab("saw", { id = "saw", transform = { move = { 0, 0, 0.125 } } }),
	prefab("output_port", { id = "out", transform = { move = { 0.75, 0.75, 0 } } }),
}
]]

test("the title, and a building drawn from its saved blueprint after its design file is gone", function()
	local config = testConfig()
	clear(config)
	assert(DesignStore.write(config.designs, "designs", "woodcutter", WOODCUTTER))

	local first = GameHarness.launch({ real = true, config = config })
	FrameStepper.step(first, 1)
	Capture.capture("title_new_only")

	-- Play a small world: place the woodcutter south of the character, save.
	local game = GameHarness.startSession(World.new(30, 20), { real = true, config = config })
	local c = game.ctx.pools.characters[1]
	c.inventory.counts.plank = 1000
	local blueprint = assert(Compile.design(WOODCUTTER, "woodcutter", Flow.library(game.flow), config))
	assert(Placement.build(game.ctx, { design = "woodcutter", blueprint = blueprint, facing = "N", tileX = 14, tileY = 12 }))
	FrameStepper.step(game, 2)
	Capture.capture("before_save")
	game:keypressed("f5")
	assert(love.filesystem.remove(config.designs.dir .. "/woodcutter.lua"), "removed the design file")

	-- A fresh config table, so its design cache has never baked the
	-- woodcutter: the sprite must come from the saved blueprint.
	config = testConfig()
	local again = GameHarness.launch({ real = true, config = config })
	assertEqual(nil, Flow.library(again.flow).designs.woodcutter)
	FrameStepper.step(again, 1)
	Capture.capture("title_continue")
	again:keypressed("return")
	assertEqual("world", again.flow.screen)
	local b = again.ctx.pools.buildings[1]
	assertTrue(b ~= nil, "expected the building loaded")
	local sprite = BuildingsRender.sprite(config, b.blueprint, b.facing, Projection.bakeScale(again.camera.zoom))
	assertTrue(sprite and sprite.image ~= nil, "expected the building's sprite baked from the saved blueprint")
	FrameStepper.step(again, 2)
	Capture.capture("after_load_design_gone")
	clear(config)
end)
