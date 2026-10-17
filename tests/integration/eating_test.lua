-- The player eats through the real input path: F eats a meal from the
-- inventory, else from a storage facility in range (docs/CONTEXT.md "Meal").
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local Inventory = require("src.game.components.inventory")
local StorageFacility = require("src.game.components.storage_facility")
local FrameStepper = require("tests.support.frame_stepper")

-- 10x10 world, player at tile (5,5); `storage` goes in a facility on tile
-- (x, y) when given.
local function start(storage, x, y)
	_G.love = LoveMock.new()
	local game = GameHarness.startSession(World.new(10, 10))
	if storage then
		GameHarness.addStorage(game.ctx, storage, x, y)
	end
	return game, Fake.FakeInput.new(), game.ctx.pools.characters[1]
end

test("F eats from the inventory until hunger is gone", function()
	local game, input, c = start()
	Inventory.add(c.inventory, "berry", 10)
	c.needs.hunger = 0.7

	Fake.holdFor(game, input, "f", 0.2)
	assertEqual(6, Inventory.count(c.inventory, "berry"))
	assertTrue(c.needs.hunger < 0.05, "hunger gone")
end)

test("F eats the highest fill first", function()
	local game, input, c = start()
	Inventory.add(c.inventory, "berry", 5)
	Inventory.add(c.inventory, "meat", 5)
	c.needs.hunger = 0.7

	Fake.holdFor(game, input, "f", 0.2)
	assertEqual(3, Inventory.count(c.inventory, "meat"))
	assertEqual(5, Inventory.count(c.inventory, "berry"))
end)

test("F with an empty inventory eats from a storage facility in range", function()
	local game, input, c = start({ berry = 10 }, 5, 7)
	c.needs.hunger = 0.7

	Fake.holdFor(game, input, "f", 0.2)
	assertEqual(6, StorageFacility.totals(game.ctx).berry)
	assertTrue(c.needs.hunger < 0.05, "hunger gone")
	assertEqual(0, Inventory.count(c.inventory, "berry"))
end)

test("F eats nothing from a facility out of range", function()
	local game, input, c = start({ berry = 10 }) -- the far corner
	c.needs.hunger = 0.7

	Fake.holdFor(game, input, "f", 0.2)
	assertEqual(10, StorageFacility.totals(game.ctx).berry)
	assertTrue(c.needs.hunger > 0.6, "still hungry")
end)

test("F when not hungry eats nothing", function()
	local game, input, c = start()
	Inventory.add(c.inventory, "berry", 3)

	Fake.holdFor(game, input, "f", 0.2)
	assertEqual(3, Inventory.count(c.inventory, "berry"))
end)

test("a new game's stockpile holds berries, and a hungry villager eats from it and goes back to idling", function()
	_G.love = LoveMock.new()
	local game = GameHarness.launch()
	Fake.tap(game, "return") -- New game
	local ctx = game.ctx
	game:update(1 / 60)
	assertEqual(Config.stockpile.berry, StorageFacility.totals(ctx).berry)
	local v = ctx.pools.villagers[1]
	v.needs.hunger = 0.7

	local ate = false
	for _ = 1, 40 * 60 do
		FrameStepper.step(game, 1)
		ate = ate or (v.job ~= nil and v.job.kind == "eat")
		if ate and not v.job then
			break
		end
	end
	assertTrue(ate, "took an eat job")
	assertEqual(nil, v.job)
	assertTrue(v.needs.hunger < 0.05, "fed")
	assertEqual(Config.stockpile.berry - 4, StorageFacility.totals(ctx).berry)
end)
