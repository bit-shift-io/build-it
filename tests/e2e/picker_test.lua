-- The building picker under real LÖVE 12: each row shows the design's
-- sprite, name and cost, and costs the storage can't cover draw red.
-- Captures land in tests/screenshots/picker_test/.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local DesignStore = require("src.app.design_store")

local DIR = "e2e_picker_designs"

local function clearDir(dir)
	for _, name in ipairs(love.filesystem.getDirectoryItems(dir)) do
		love.filesystem.remove(dir .. "/" .. name)
	end
end

local function brick(shape, x, y, z, width, depth, paint)
	return { shape = shape, rotation = 0, x = x, y = y, z = z, width = width, depth = depth, material = "plank", paint = paint }
end

-- A big and a small design, so thumbnails differ in size and the small one
-- is affordable where the big one is not.
local function bigDesign()
	local bricks = {}
	for z = 0, 3 do
		for x = 0, 8, 4 do
			table.insert(bricks, brick("2x4", x, 0, z, 4, 2, 4))
		end
	end
	return { id = "d1", name = "E2E Big Hall", versions = { { width = 3, depth = 1, bricks = bricks } } }
end

local function smallDesign()
	return { id = "d2", name = "E2E Small Hut", versions = { { width = 1, depth = 1, bricks = { brick("2x2", 0, 0, 0, 2, 2, 1) } } } }
end

test("picker rows show thumbnail, name and cost, short items in red", function()
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.designs = { dir = DIR, maxNameLength = Config.designs.maxNameLength }
	clearDir(DIR)
	assert(DesignStore.write(DIR, bigDesign()))
	assert(DesignStore.write(DIR, smallDesign()))

	local game = GameHarness.startSession(World.new(30, 20), { real = true, config = config, storage = { plank = 2 } })
	Fake.tap(game, "1")
	assertTrue(game.flow.world.picker ~= nil, "expected the picker open")
	game:mousemoved(5, 5, 0, 0)
	Capture.capture("picker_rows")
	clearDir(DIR)
end)
