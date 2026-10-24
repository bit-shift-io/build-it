-- A new player's first chain with no builder: the shipped starter
-- woodcutter (content/designs/woodcutter.lua), picked by name and placed
-- with a click, is run by a villager who never stands in a wall, and its
-- logs reach storage; the
-- starter sawmill and every other starter building are in the picker.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local Session = require("src.game.session")
local Inventory = require("src.game.components.inventory")
local Walls = require("tests.support.walls")

local TILE = Config.tileSize

-- 20x20 world, character at its centre on tile (10, 10), trees in columns
-- 11 and 14, rows 4..6; nothing in the design store. Storage holds
-- `storage` (default the stockpile).
local function launch(storage)
	_G.love = LoveMock.new()
	local world = World.new(20, 20)
	local id = 0
	for y = 4, 6 do
		for _, x in ipairs({ 11, 14 }) do
			id = id + 1
			World.addNode(world, { id = id, kind = "tree", tileX = x, tileY = y, variant = 1, stage = 1, amount = Config.nodes.tree.amount })
		end
	end
	local game = GameHarness.startSession(world, { storage = storage or Config.stockpile })
	return game, game.ctx.pools.characters[1], world
end

test("the starter woodcutter is placed from the picker and a villager brings logs to storage, never standing in a wall", function()
	local game, c = launch()
	local facility = game.ctx.pools.buildings[1]
	table.insert(game.ctx.pools.villagers, Session.newVillager(1, 5.5 * TILE, 12.5 * TILE, Config))

	Fake.pickDesign(game, "woodcutter")
	Fake.click(game, 1, 640 + (13 * TILE - c.x), 360 + (7.5 * TILE - c.y))
	GameHarness.completeSites(game)
	local b = game.ctx.pools.buildings[2]
	assert(b, "the woodcutter was placed")
	assertEqual("woodcutter", b.design)

	local logs = facility.storage.counts.log or 0
	Fake.runUntil(game, function()
		local inWall = Walls.villagerInWall(game.ctx)
		assert(not inWall, inWall)
		return (facility.storage.counts.log or 0) >= logs + 4
	end, 60 * 120)
	assertEqual(0, Inventory.count(c.inventory, "log"), "the player did nothing")
end)
