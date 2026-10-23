-- The building picker under real LÖVE 12: each row shows the design's
-- sprite, name and cost, and costs the storage can't cover draw red.
-- Captures land in tests/screenshots/picker_test/.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local DesignStore = require("src.app.design_store")

local DIRS = { dir = "e2e_picker_designs", prefabDir = "e2e_picker_prefabs" }

local function clearDir(dir)
	for _, name in ipairs(love.filesystem.getDirectoryItems(dir)) do
		love.filesystem.remove(dir .. "/" .. name)
	end
end

-- A big and a small design, so thumbnails differ in size and the small one
-- is affordable where the big one is not. Each has a bed, so the picker
-- offers it.
local BIG = [[
return group{ id = "root", name = "Big hall",
	box{ id = "hall", size = { 3, 1, 1 } },
	prefab("bed", { id = "bed", transform = { move = { 0.25, 0.25, 1 } } }),
}
]]

local SMALL = [[
return group{ id = "root", name = "Small hut",
	box{ id = "floor", size = { 1, 1, 0.0625 } },
	role{ id = "bed", ability = "bed", transform = { move = { 0.5, 0.5, 0 } } },
}
]]

test("picker rows show thumbnail, name and cost, short items in red", function()
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.designs = DIRS
	clearDir(DIRS.dir)
	clearDir(DIRS.prefabDir)
	assert(DesignStore.write(DIRS, "designs", "e2e_big_hall", BIG))
	assert(DesignStore.write(DIRS, "designs", "e2e_small_hut", SMALL))

	local game = GameHarness.startSession(World.new(30, 20), { real = true, config = config, storage = { plank = 10 } })
	Fake.tap(game, "1")
	assertTrue(game.flow.world.picker ~= nil, "expected the picker open")
	game:mousemoved(5, 5, 0, 0)
	Capture.capture("picker_rows")
	clearDir(DIRS.dir)
end)
