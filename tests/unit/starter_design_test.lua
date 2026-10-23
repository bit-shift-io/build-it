-- The built-in starting storage facility (docs/CONTEXT.md "Storage
-- facility", "Depot"): the Lua design content/designs/storage_facility.lua,
-- compiled (src/game/buildings/compile.lua), addressed by name.
local Starter = require("src.game.designs.starter")
local Config = require("src.game.config")
local Builtins = require("tests.support.builtins")

test("the starter blueprint compiles from the Lua design with a depot, storage and both ports", function()
	local bp = Starter.blueprint(Builtins, Config)
	assertEqual("depot", bp.roles.abilities[1].ability)
	assertTrue(bp.roles.storage > 0, "has storage")
	local kinds = {}
	for _, p in ipairs(bp.roles.ports) do
		kinds[p.kind] = (kinds[p.kind] or 0) + 1
	end
	assertEqual(1, kinds.input)
	assertEqual(1, kinds.output)
end)

local Library = require("src.game.designs.library")

test("a saved design named like the starter shadows the built-in one", function()
	local mine = [[return group{ box{ size = { 2, 2, 1 } }, prefab("depot", { transform = { move = { 0.5, 0.5, 0 } } }) }]]
	local bp = Starter.blueprint(Library.merge(Builtins, { designs = { [Starter.NAME] = mine } }), Config)
	assertEqual(2, bp.width)
	assertEqual(2, bp.depth)
	assertEqual(0, #bp.roles.ports)
end)

local Session = require("src.game.session")
local World = require("src.game.world")
local WorldGen = require("src.game.world_gen")
local StorageFacility = require("src.game.components.storage_facility")
local Inventory = require("src.game.components.inventory")

test("a new game places the starter facility at the world centre with the stockpile in its storage", function()
	local world = WorldGen.generate(Config, 1)
	local ctx = Session.newGame(world, Config, 1, Builtins)

	assertEqual(1, #ctx.pools.buildings)
	local b = ctx.pools.buildings[1]
	assertEqual(Starter.NAME, b.design)
	assertEqual(b, World.buildingAt(ctx.world, math.floor(world.width / 2), math.floor(world.height / 2)), "covers the centre tile")
	assertEqual(1, #StorageFacility.all(ctx))
	assertEqual(Config.stockpile.plank, b.storage.counts.plank)
	assertEqual(Config.stockpile.stone, b.storage.counts.stone)
end)

test("a new game's player starts outside the facility with no planks or stone", function()
	local ctx = Session.newGame(WorldGen.generate(Config, 1), Config, 1, Builtins)
	local c = ctx.pools.characters[1]
	local tile = Config.tileSize
	local x, y = math.floor(c.x / tile), math.floor(c.y / tile)

	assertFalse(World.isBlocked(ctx.world, x, y), "the player stands on an open tile")
	assertEqual(0, Inventory.count(c.inventory, "plank"))
	assertEqual(0, Inventory.count(c.inventory, "stone"))
end)
