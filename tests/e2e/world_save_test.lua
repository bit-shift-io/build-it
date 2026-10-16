-- World save and load under real LÖVE 12: the title screen, and a saved
-- building whose design file is gone from the library still drawing from
-- the save's snapshot. Uses its own save file and designs dir, cleared
-- first. Captures land in tests/screenshots/world_save_test/.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local FrameStepper = require("tests.support.frame_stepper")
local Config = require("src.game.config")
local World = require("src.game.world")
local DesignStore = require("src.app.design_store")
local Placement = require("src.game.buildings.placement")
local BuildingsRender = require("src.app.render.buildings")
local Projection = require("src.game.projection")

local function testConfig()
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.designs = { dir = "e2e_save_designs", maxNameLength = Config.designs.maxNameLength }
	config.save = { file = "e2e_world.save", seed = Config.save.seed }
	return config
end

local function clear(config)
	for _, name in ipairs(love.filesystem.getDirectoryItems(config.designs.dir)) do
		love.filesystem.remove(config.designs.dir .. "/" .. name)
	end
	love.filesystem.remove(config.save.file)
end

local function brick(shape, x, y, z, width, depth, paint, f)
	f = f or {}
	return { shape = shape, rotation = 0, x = x, y = y, z = z, width = width, depth = depth, height = f.height or 1, material = "plank", paint = paint, ability = f.ability, port = f.port }
end

-- A 2x1 tile woodcutter: a saw, a red tower and an orange output port.
local function woodcutter()
	local bricks = {
		brick("saw", 0, 0, 0, 3, 1, 1, { height = 3, ability = "saw" }),
		brick("output", 3, 3, 0, 2, 1, 2, { port = "output" }),
	}
	for z = 0, 4 do
		table.insert(bricks, brick("2x2", 6, 0, z, 2, 2, 1))
	end
	return { id = "d1", name = "Woodcutter", versions = { { width = 2, depth = 1, bricks = bricks } } }
end

test("the title, and a building drawn from the save's snapshot after its design file is gone", function()
	local config = testConfig()
	clear(config)
	assert(DesignStore.write(config.designs.dir, woodcutter()))

	local first = GameHarness.launch({ real = true, config = config })
	FrameStepper.step(first, 1)
	Capture.capture("title_new_only")

	-- Play a small world: place the woodcutter south of the character, save.
	local game = GameHarness.startSession(World.new(30, 20), { real = true, config = config })
	local c = game.ctx.pools.characters[1]
	c.inventory.counts.plank = 1000
	local library = game.flow.library
	assert(Placement.place(game.ctx, c, { design = library.designs[1], version = 1, facing = "N", tileX = 14, tileY = 12 }))
	FrameStepper.step(game, 2)
	Capture.capture("before_save")
	game:keypressed("f5")
	assert(love.filesystem.remove(config.designs.dir .. "/d1.design"), "removed the design file")

	-- A fresh config table, so its design cache has never baked d1: the
	-- sprite must come from the snapshot.
	config = testConfig()
	local again = GameHarness.launch({ real = true, config = config })
	assertEqual(0, #again.flow.library.designs)
	FrameStepper.step(again, 1)
	Capture.capture("title_continue")
	again:keypressed("return")
	assertEqual("world", again.flow.screen)
	local b = again.ctx.pools.buildings[1]
	assertTrue(b ~= nil, "expected the building loaded")
	local sprite = BuildingsRender.sprite(config, b.design, b.version, b.facing, Projection.bakeScale(again.camera.zoom))
	assertTrue(sprite and sprite.image ~= nil, "expected the building's sprite baked from the snapshot")
	FrameStepper.step(again, 2)
	Capture.capture("after_load_design_gone")
	clear(config)
end)
