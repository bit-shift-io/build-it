-- The starting storage facility through the real input path: New game on
-- the title screen places it at the world centre with the stockpile in its
-- storage, and logs the player delivers at its depot's input port (E on the
-- port tile) join the storage totals.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local Inventory = require("src.game.components.inventory")
local StorageFacility = require("src.game.components.storage_facility")
local Starter = require("src.game.designs.starter")

local TILE = Config.tileSize

local function newGame()
	_G.love = LoveMock.new()
	local game = GameHarness.launch()
	Fake.tap(game, "return") -- New game, the only option with no save
	assertEqual("world", game.flow.screen)
	return game, Fake.FakeInput.new(), game.ctx.pools.characters[1]
end

test("a new game shows the storage facility at the centre holding the stockpile, the inventory empty", function()
	local game, _, c = newGame()
	local facilities = StorageFacility.all(game.ctx)
	assertEqual(1, #facilities)
	assertEqual(Starter.ID, facilities[1].design.id)
	local w, h = game.ctx.world.width, game.ctx.world.height
	assertEqual(facilities[1], World.buildingAt(game.ctx.world, math.floor(w / 2), math.floor(h / 2)))

	game:update(1 / 60)
	local totals = StorageFacility.totals(game.ctx)
	assertEqual(Config.stockpile.plank, totals.plank)
	assertEqual(Config.stockpile.stone, totals.stone)
	assertEqual(0, Inventory.count(c.inventory, "plank"))
	assertEqual(0, Inventory.count(c.inventory, "stone"))
end)

test("logs delivered at the depot's input port with E raise the storage totals", function()
	local game, input, c = newGame()
	local facility = StorageFacility.all(game.ctx)[1]
	local port
	for _, p in ipairs(facility.ports) do
		if p.kind == "input" then
			port = p
		end
	end
	Inventory.add(c.inventory, "log", 3)

	Fake.holdFor(game, input, "w", 0.2) -- north onto the input port tile
	assertEqual(port, World.portAt(game.ctx.world, math.floor(c.x / TILE), math.floor(c.y / TILE)), "standing on the input port")
	Fake.holdFor(game, input, "e", 1 / 60)

	assertEqual(0, Inventory.count(c.inventory, "log"), "all logs delivered")
	Fake.holdFor(game, input, "s", 1 / 60)
	assertEqual(3, StorageFacility.totals(game.ctx).log)
	assertEqual(0, port.buffer.counts.log or 0, "the depot moved them out of the input")
end)
