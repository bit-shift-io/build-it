-- A forester and a woodcutter side by side, through the real input path:
-- a villager runs the forester and plants saplings, they grow (growth time overridden to a few
-- seconds), and a villager runs the woodcutter's saw on the grown trees.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local DesignStore = require("src.app.design_store")
local Designs = require("tests.support.designs")
local Session = require("src.game.session")

local TILE = Config.tileSize

-- A planter (or a saw) on the north row of a 2x1 tile floor and an output
-- port on its south edge under tile (1, 0).
local FORESTER = Designs.floor(2, 1, Designs.ability("planter", 0.375, 0.125), Designs.port("output", 1, 1))
local WOODCUTTER = Designs.floor(2, 1, Designs.ability("saw", 0.375, 0.125), Designs.port("output", 1, 1))

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
	assert(DesignStore.write(Config.designs, "designs", "forester", FORESTER))
	assert(DesignStore.write(Config.designs, "designs", "woodcutter", WOODCUTTER))
	local world = World.new(20, 20)
	local config = fastConfig()
	local game = GameHarness.startSession(world, { config = config, storage = config.stockpile })
	local c = game.ctx.pools.characters[1]
	local facility = game.ctx.pools.buildings[1]
	-- One villager operates the forester, one the woodcutter, one hauls.
	for i = 1, 3 do
		table.insert(game.ctx.pools.villagers, Session.newVillager(i, (4 + i) * TILE, 12.5 * TILE, Config))
	end

	Fake.pickDesign(game, "forester")
	Fake.click(game, 1, 640 + (13 * TILE - c.x), 360 + (7.5 * TILE - c.y))
	Fake.pickDesign(game, "wood")
	Fake.click(game, 1, 640 + (13 * TILE - c.x), 360 + (10.5 * TILE - c.y))
	GameHarness.completeSites(game)
	local forester, cutter = game.ctx.pools.buildings[2], game.ctx.pools.buildings[3] -- after the storage facility
	assert(forester and cutter, "both buildings were placed")

	Fake.runUntil(game, function()
		return (facility.storage.counts.log or 0) > 0
	end, 60 * 120)
	assertTrue(facility.storage.counts.log > 0, "a villager harvested a grown tree and storage holds the log")

	for _, n in ipairs(game.ctx.pools.nodes) do
		assertEqual("grass", World.terrainAt(world, n.tileX, n.tileY))
		assertEqual(nil, World.buildingAt(world, n.tileX, n.tileY))
		assertEqual(nil, World.portAt(world, n.tileX, n.tileY))
	end
end)
