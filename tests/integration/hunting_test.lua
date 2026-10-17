-- A hunter brick beside a herd, through the real input path: the design is
-- a real file in love_mock's save directory, placed with a number key and
-- a click; a villager hunts deer in reach, and hauls take the meat on to storage;
-- the herd breeds back.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local Inventory = require("src.game.components.inventory")
local DesignStore = require("src.app.design_store")
local Session = require("src.game.session")
local AnimalSystem = require("src.game.systems.animal_system")

local TILE = Config.tileSize

local HUNTER = {
	id = "d3",
	name = "Hunter",
	versions = {
		{
			width = 2,
			depth = 1,
			bricks = {
				{ x = 0, y = 0, z = 0, width = 3, depth = 1, height = 3, shape = "hunter", rotation = 0, material = "plank", paint = 1, ability = "hunter" },
				{ x = 3, y = 3, z = 0, width = 2, depth = 1, height = 1, shape = "output", rotation = 0, material = "plank", paint = 2, port = "output" },
			},
		},
	},
}

test("a hunter building kills deer in reach and delivers meat to storage; the herd breeds back", function()
	_G.love = LoveMock.new()
	assert(DesignStore.write(Config.designs.dir, HUNTER))
	local game = GameHarness.startSession(World.new(30, 30), { storage = Config.stockpile })
	local ctx, c = game.ctx, game.ctx.pools.characters[1]
	local facility = ctx.pools.buildings[1]
	table.insert(ctx.pools.villagers, Session.newVillager(1, 5.5 * TILE, 12.5 * TILE, Config))
	local herd = AnimalSystem.addHerd(ctx, 17, 8, 3)
	for i = 1, 3 do
		AnimalSystem.spawn(ctx, herd, 16 + i, 8)
	end

	Fake.tap(game, "1")
	Fake.click(game, 1, 640 + (13 * TILE - c.x), 360 + (7.5 * TILE - c.y))
	GameHarness.completeSites(game)
	assert(ctx.pools.buildings[2], "the hunter building was placed")

	local per = Config.production.meatPerDeer
	local start = facility.storage.counts.meat or 0
	Fake.runUntil(game, function()
		return (facility.storage.counts.meat or 0) >= start + per
	end, 60 * 600)
	assertTrue((facility.storage.counts.meat or 0) >= start + per, "meat reached storage")

	local spawned = ctx.nextAnimalId
	Fake.runUntil(game, function()
		return ctx.nextAnimalId > spawned
	end, 60 * 900)
	assertTrue(ctx.nextAnimalId > spawned, "the herd bred a new deer after the kills")
end)
