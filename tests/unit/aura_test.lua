-- Auras: bonuses within a building's reach, additive, applied to speed and harvest.
local Session = require("src.game.session")
local World = require("src.game.world")
local Config = require("src.game.config")
local Placement = require("src.game.buildings.placement")
local Inventory = require("src.game.components.inventory")
local Aura = require("src.game.components.aura")
local Traits = require("src.game.builder.traits")
local Walker = require("src.game.components.walker")
local VillagerSystem = require("src.game.systems.villager_system")

local function design(material)
	local bricks = { { x = 0, y = 0, z = 0, width = 2, depth = 2, height = 1, shape = "2x2", rotation = 0, material = material, paint = 1 } }
	return { id = "d", name = "A", versions = { { width = 1, depth = 1, bricks = bricks } } }
end

local function setup(material)
	local ctx = Session.new(World.new(50, 50), Config, 1)
	local c = ctx.pools.characters[1]
	c.inventory = Inventory.new({ plank = 10000, stone = 10000 })
	assert(Placement.build(ctx, { design = design(material), version = 1, facing = "N", tileX = 10, tileY = 10 }))
	return ctx, c
end

local function at(ctx, c, tx, ty)
	c.x, c.y = (tx + 0.5) * Config.tileSize, (ty + 0.5) * Config.tileSize
	return Aura.at(ctx, c)
end

test("aura applies in reach and not outside", function()
	local ctx, c = setup("plank")
	assertEqual(Config.auras.plank.walkSpeed, at(ctx, c, 11, 10).walkSpeed)
	assertEqual(0, at(ctx, c, 40, 40).walkSpeed)
end)

test("auras stack additively", function()
	local ctx, c = setup("plank")
	assert(Placement.build(ctx, { design = design("plank"), version = 1, facing = "N", tileX = 13, tileY = 10 }))
	assertNear(2 * Config.auras.plank.walkSpeed, at(ctx, c, 12, 10).walkSpeed)
end)

test("a speed aura makes the character faster and leaving removes it", function()
	local ctx, c = setup("plank")
	c.x, c.y = 12.5 * Config.tileSize, 10.5 * Config.tileSize
	local x0 = c.x
	ctx.intents[c.player] = { x = 1, y = 0 }
	Session.advance(ctx, 1 / 60)
	assertEqual(Config.character.speed, c.mover.speed)
	assertTrue(c.x - x0 > Config.character.speed / 60 + 1e-9)
	c.x = 25.5 * Config.tileSize
	x0 = c.x
	Session.advance(ctx, 1 / 60)
	assertNear(Config.character.speed / 60, c.x - x0, 1e-6)
end)

test("a harvest aura shortens the hand-harvest cycle", function()
	local ctx, c = setup("stone")
	ctx.pools.buildings[1].aura.harvestRate = 1 -- double speed
	local inside = Aura.at(ctx, { x = 12.5 * Config.tileSize, y = 10.5 * Config.tileSize })
	assertEqual(1, inside.harvestRate)
end)

test("builder aura totals sum material auras", function()
	assertEqual(Config.auras.stone.harvestRate, Traits.auras(design("stone").versions[1], Config).harvestRate)
end)

test("Aura.lines formats one decimal and hides zero auras", function()
	local lines = Aura.lines({ walkSpeed = 0.005, harvestRate = 0.001 })
	assertEqual(2, #lines)
	assertEqual("Walk speed +0.5%", lines[1])
	assertEqual("Work rate +0.1%", lines[2])
	local one = Aura.lines({ walkSpeed = 0, harvestRate = 0.001 })
	assertEqual(1, #one)
	assertEqual(0, #Aura.lines({ walkSpeed = 0, harvestRate = 0 }))
end)

-- A villager at tile (tx, ty) walking east 5 tiles for `steps` steps.
local function villagerWalk(ctx, tx, ty, steps)
	local v = Session.newVillager(1, (tx + 0.5) * Config.tileSize, (ty + 0.5) * Config.tileSize, Config)
	ctx.pools.villagers = { v }
	assertTrue(Walker.goTo(v, ctx, tx + 5, ty))
	ctx.dt = 1 / 60
	local x0 = v.x
	for _ = 1, steps do
		VillagerSystem.update(ctx)
	end
	return v, v.x - x0
end

test("a villager in reach walks faster by its aura; one outside is unchanged", function()
	local ctx = setup("plank")
	ctx.pools.buildings[1].aura.walkSpeed = 1 -- double speed
	local inside, dIn = villagerWalk(ctx, 12, 10, 10)
	assertNear(1, inside.aura.walkSpeed)
	assertEqual(Config.villagers.speed, inside.mover.speed, "speed restored after the step")
	local outside, dOut = villagerWalk(ctx, 30, 30, 10)
	assertEqual(0, outside.aura.walkSpeed)
	assertNear(2, dIn / dOut, 1e-6)
end)
