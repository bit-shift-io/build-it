-- A forester and a woodcutter side by side, through the real input path:
-- the forester plants saplings, they grow (growth time overridden to a few
-- seconds), and the woodcutter's saw harvests the grown trees.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local DesignStore = require("src.app.design_store")

local TILE = Config.tileSize

local FORESTER = {
	id = "d1",
	name = "Forester",
	versions = { { width = 2, depth = 1, bricks = {
		{ x = 0, y = 0, z = 0, width = 3, depth = 1, height = 3, shape = "planter", rotation = 0, material = "plank", paint = 1, ability = "planter" },
		{ x = 3, y = 3, z = 0, width = 2, depth = 1, height = 1, shape = "output", rotation = 0, material = "plank", paint = 2, port = "output" },
	} } },
}

local WOODCUTTER = {
	id = "d2",
	name = "Woodcutter",
	versions = { { width = 2, depth = 1, bricks = {
		{ x = 0, y = 0, z = 0, width = 3, depth = 1, height = 3, shape = "saw", rotation = 0, material = "plank", paint = 1, ability = "saw" },
		{ x = 3, y = 3, z = 0, width = 2, depth = 1, height = 1, shape = "output", rotation = 0, material = "plank", paint = 2, port = "output" },
	} } },
}

local function fastConfig()
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.nodes = { tree = { amount = 3, item = "log", stageAt = { 0.6, 0.3 }, growTime = 4 }, rock = Config.nodes.rock }
	config.stockpile = { plank = 1000, stone = 1000 }
	config.production = {}
	for k, v in pairs(Config.production) do
		config.production[k] = v
	end
	config.production.plantCycle = 1
	return config
end

test("a forester replants and a woodcutter harvests the grown trees", function()
	_G.love = LoveMock.new()
	assert(DesignStore.write(Config.designs.dir, FORESTER))
	assert(DesignStore.write(Config.designs.dir, WOODCUTTER))
	local world = World.new(20, 20)
	local game = GameHarness.startSession(world, { config = fastConfig() })
	local c = game.ctx.pools.characters[1]

	Fake.tap(game, "1")
	Fake.click(game, 1, 640 + (13 * TILE - c.x), 360 + (7.5 * TILE - c.y))
	Fake.tap(game, "2")
	Fake.click(game, 1, 640 + (13 * TILE - c.x), 360 + (10.5 * TILE - c.y))
	local forester, cutter = game.ctx.pools.buildings[1], game.ctx.pools.buildings[2]
	assert(forester and cutter, "both buildings were placed")

	Fake.runUntil(game, function()
		return (cutter.ports[1].buffer.counts.log or 0) > 0
	end, 60 * 120)
	assertTrue(cutter.ports[1].buffer.counts.log > 0, "the woodcutter harvested a grown tree")

	for _, n in ipairs(game.ctx.pools.nodes) do
		assertEqual("grass", World.terrainAt(world, n.tileX, n.tileY))
		assertEqual(nil, World.buildingAt(world, n.tileX, n.tileY))
		assertEqual(nil, World.portAt(world, n.tileX, n.tileY))
	end
end)
