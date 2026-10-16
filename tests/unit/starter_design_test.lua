-- The built-in starting storage facility design (docs/CONTEXT.md
-- "Storage facility", "Depot"): a valid design with a depot, storage
-- bricks and both ports, under a reserved id.
local Starter = require("src.game.designs.starter")
local Validate = require("src.game.builder.validate")
local Config = require("src.game.config")

local function count(version, test)
	local n = 0
	for _, b in ipairs(version.bricks) do
		if test(b) then
			n = n + 1
		end
	end
	return n
end

test("the starter design is valid and has a depot, storage and both ports", function()
	local design = Starter.design(Config)
	local version = design.versions[1]
	assertEqual(0, #Validate.problems(version, Config.builder), table.concat(Validate.problems(version, Config.builder), ", "))
	assertEqual(1, count(version, function(b)
		return b.ability == "depot"
	end))
	assertTrue(count(version, function(b)
		return b.storage ~= nil
	end) > 0, "has storage bricks")
	assertEqual(1, count(version, function(b)
		return b.port == "input"
	end))
	assertEqual(1, count(version, function(b)
		return b.port == "output"
	end))
end)

test("the starter design has a reserved id outside the library's dN scheme", function()
	local design = Starter.design(Config)
	assertEqual(Starter.ID, design.id)
	assertFalse(design.id:match("^d%d+$") ~= nil, "id must not look like a library id")
end)

local Session = require("src.game.session")
local World = require("src.game.world")
local WorldGen = require("src.game.world_gen")
local StorageFacility = require("src.game.components.storage_facility")
local Inventory = require("src.game.components.inventory")

test("a new game places the starter facility at the world centre with the stockpile in its storage", function()
	local world = WorldGen.generate(Config, 1)
	local ctx = Session.newGame(world, Config, 1)

	assertEqual(1, #ctx.pools.buildings)
	local b = ctx.pools.buildings[1]
	assertEqual(Starter.ID, b.design.id)
	assertEqual(b, World.buildingAt(ctx.world, math.floor(world.width / 2), math.floor(world.height / 2)), "covers the centre tile")
	assertEqual(1, #StorageFacility.all(ctx))
	assertEqual(Config.stockpile.plank, b.storage.counts.plank)
	assertEqual(Config.stockpile.stone, b.storage.counts.stone)
end)

test("a new game's player starts outside the facility with no planks or stone", function()
	local ctx = Session.newGame(WorldGen.generate(Config, 1), Config, 1)
	local c = ctx.pools.characters[1]
	local tile = Config.tileSize
	local x, y = math.floor(c.x / tile), math.floor(c.y / tile)

	assertFalse(World.isBlocked(ctx.world, x, y), "the player stands on an open tile")
	assertEqual(0, Inventory.count(c.inventory, "plank"))
	assertEqual(0, Inventory.count(c.inventory, "stone"))
end)
