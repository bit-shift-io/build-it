-- E on ports (docs/CONTEXT.md "Port", "Faced tile"): the player collects or
-- delivers at the port underfoot, else at the port on the faced tile.
local Session = require("src.game.session")
local World = require("src.game.world")
local Config = require("src.game.config")
local Placement = require("src.game.buildings.placement")
local Inventory = require("src.game.components.inventory")
local Storage = require("src.game.components.storage")
local Character = require("src.game.props.character")
local CharacterSystem = require("src.game.systems.character_system")

local TILE = Config.tileSize

local function brick(shape, x, y, f)
	return { x = x, y = y, z = 0, width = f.width, depth = f.depth, height = 1, shape = shape, rotation = 0, material = "plank", paint = 1, ability = f.ability, port = f.port }
end

local function design()
	local bricks = {
		brick("input", 0, 3, { width = 2, depth = 1, port = "input" }),
		brick("output", 4, 3, { width = 2, depth = 1, port = "output" }),
		brick("sawbench", 0, 0, { width = 4, depth = 2, ability = "sawbench" }),
	}
	return { id = "d1", name = "Mill", versions = { { width = 2, depth = 1, bricks = bricks } } }
end

local function setup()
	local ctx = Session.new(World.new(30, 30), Config, 1)
	local b = assert(Placement.build(ctx, { design = design(), version = 1, facing = "N", tileX = 10, tileY = 10 }))
	local input, output
	for _, p in ipairs(b.ports) do
		if p.kind == "input" then
			input = p
		else
			output = p
		end
	end
	return ctx, ctx.pools.characters[1], input, output
end

local function stand(c, tx, ty, facing)
	c.x, c.y = (tx + 0.5) * TILE, (ty + 0.5) * TILE
	c.animator.facing = facing
end

local function indexOf(name)
	for i, d in ipairs(Character.DIRECTIONS) do
		if d.name == name then
			return i
		end
	end
end

test("the faced tile is the neighbour in each of the 8 facings", function()
	local ctx, c = setup()
	for i, d in ipairs(Character.DIRECTIONS) do
		stand(c, 3, 3, i)
		local x, y = CharacterSystem.facedTile(c, ctx)
		assertEqual(3 + d.x, x)
		assertEqual(3 + d.y, y)
	end
end)

test("portInUse is nil with no port underfoot or faced", function()
	local ctx, c = setup()
	stand(c, 1, 1, indexOf("E"))
	assertEqual(nil, CharacterSystem.portInUse(c, ctx))
end)

test("portInUse finds the port underfoot", function()
	local ctx, c, input = setup()
	stand(c, input.x, input.y, indexOf("N"))
	assertTrue(CharacterSystem.portInUse(c, ctx) == input, "underfoot input port")
end)

test("portInUse finds the faced port, diagonals included", function()
	local ctx, c, _, output = setup()
	stand(c, output.x - 1, output.y - 1, indexOf("SE"))
	assertTrue(CharacterSystem.portInUse(c, ctx) == output, "faced output port")
end)

test("underfoot port wins over the faced one", function()
	local ctx, c, input, output = setup()
	-- put the output port on the tile north of the input port
	ctx.world.portAt[(input.y - 1) * ctx.world.width + input.x + 1] = output
	stand(c, input.x, input.y, indexOf("N"))
	assertTrue(CharacterSystem.portInUse(c, ctx) == input, "underfoot wins")
end)

test("E facing an output port collects its buffer", function()
	local ctx, c, _, output = setup()
	Storage.add(output.buffer, "plank")
	Storage.add(output.buffer, "plank")
	stand(c, output.x, output.y - 1, indexOf("S"))
	ctx.intents[c.player] = { x = 0, y = 0, harvest = true }
	CharacterSystem.update(ctx)
	assertEqual(2, Inventory.count(c.inventory, "plank"))
	assertEqual(0, Storage.total(output.buffer))
end)

test("E facing an input port delivers accepted items only", function()
	local ctx, c, input = setup()
	Inventory.add(c.inventory, "log", 3)
	Inventory.add(c.inventory, "stone", 2)
	stand(c, input.x, input.y - 1, indexOf("S"))
	ctx.intents[c.player] = { x = 0, y = 0, harvest = true }
	CharacterSystem.update(ctx)
	assertEqual(3, input.buffer.counts.log)
	assertEqual(nil, input.buffer.counts.stone)
	assertEqual(2, Inventory.count(c.inventory, "stone"))
end)

-- Water on the tile east of (3, 3); the player stands on (3, 3).
local function pond()
	local ctx, c = setup()
	World.setTerrain(ctx.world, 4, 3, "water")
	stand(c, 3, 3, indexOf("E"))
	return ctx, c
end

local function hold(ctx, c, seconds, target)
	ctx.intents[c.player] = { x = 0, y = 0, harvest = true, target = target }
	ctx.dt = 1 / 60
	for _ = 1, math.floor(seconds * 60 + 0.5) do
		CharacterSystem.update(ctx)
	end
end

test("holding E facing water catches one fish per hand cycle", function()
	local ctx, c = pond()
	hold(ctx, c, Config.harvest.handCycle * 3 + 0.05)
	assertEqual(3, Inventory.count(c.inventory, "fish"))
end)

test("turning away from the water resets fishing progress", function()
	local ctx, c = pond()
	hold(ctx, c, Config.harvest.handCycle * 0.8)
	c.animator.facing = indexOf("S")
	hold(ctx, c, 1 / 60)
	assertEqual(0, c.harvester.progress)
	c.animator.facing = indexOf("E")
	hold(ctx, c, Config.harvest.handCycle * 0.8)
	assertEqual(0, Inventory.count(c.inventory, "fish"))
end)

test("releasing E resets fishing progress", function()
	local ctx, c = pond()
	hold(ctx, c, Config.harvest.handCycle * 0.8)
	ctx.intents[c.player] = { x = 0, y = 0 }
	CharacterSystem.update(ctx)
	assertEqual(0, c.harvester.progress)
end)

test("faced water beats a nearby tree; a clicked tree beats faced water; grass still chops", function()
	local ctx, c = pond()
	local tree = World.addNode(ctx.world, { id = 1, kind = "tree", tileX = 3, tileY = 2, variant = 1, stage = 1, amount = 5 })
	c.y = 3 * TILE + 2 -- on the tree's edge of the tile, within reach
	hold(ctx, c, Config.harvest.handCycle + 0.05)
	assertEqual(1, Inventory.count(c.inventory, "fish"))
	assertEqual(5, tree.amount)
	hold(ctx, c, Config.harvest.handCycle + 0.05, { x = 3, y = 2 })
	assertEqual(4, tree.amount)
	c.animator.facing = indexOf("W")
	hold(ctx, c, Config.harvest.handCycle + 0.05)
	assertEqual(3, tree.amount)
end)
