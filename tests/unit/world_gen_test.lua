local WorldGen = require("src.game.world_gen")
local World = require("src.game.world")
local Config = require("src.game.config")

-- The whole world as one comparable string: every tile's terrain, then every
-- node in pool order.
local function signature(world)
	local parts = {}
	for y = 0, world.height - 1 do
		for x = 0, world.width - 1 do
			parts[#parts + 1] = World.terrainAt(world, x, y) == "water" and "~" or "."
		end
	end
	for _, n in ipairs(world.nodes) do
		parts[#parts + 1] = string.format("|%d:%s@%d,%d v%d s%d a%d", n.id, n.kind, n.tileX, n.tileY, n.variant, n.stage, n.amount)
	end
	return table.concat(parts)
end

test("the same seed gives an identical world", function()
	assertEqual(signature(WorldGen.generate(Config, 7)), signature(WorldGen.generate(Config, 7)))
end)

test("different seeds give different worlds", function()
	assertTrue(signature(WorldGen.generate(Config, 7)) ~= signature(WorldGen.generate(Config, 8)))
end)

test("a world is the configured size, with water and both node kinds", function()
	local world = WorldGen.generate(Config, 3)
	assertEqual(Config.world.width, world.width)
	assertEqual(Config.world.height, world.height)
	local water, kinds = 0, {}
	for y = 0, world.height - 1 do
		for x = 0, world.width - 1 do
			if World.terrainAt(world, x, y) == "water" then
				water = water + 1
			end
		end
	end
	for _, n in ipairs(world.nodes) do
		kinds[n.kind] = (kinds[n.kind] or 0) + 1
	end
	assertTrue(water > 0, "expected some water")
	assertTrue(water < world.width * world.height / 3, "expected mostly land, got " .. water .. " water tiles")
	assertTrue((kinds.tree or 0) > 100, "expected forests, got " .. tostring(kinds.tree) .. " trees")
	assertTrue((kinds.rock or 0) > 20, "expected rocks, got " .. tostring(kinds.rock) .. " rocks")
end)

test("every node sits alone on grass, at full stage with its kind's amount and a valid variant", function()
	for seed = 1, 5 do
		local world = WorldGen.generate(Config, seed)
		for _, n in ipairs(world.nodes) do
			assertEqual("grass", World.terrainAt(world, n.tileX, n.tileY), "node " .. n.id .. " on grass")
			assertEqual(n, World.nodeAt(world, n.tileX, n.tileY), "node " .. n.id .. " alone on its tile")
			assertEqual(1, n.stage)
			assertEqual(Config.nodes[n.kind].amount, n.amount)
			assertTrue(n.variant >= 1 and n.variant <= Config.props.variants, "variant in range")
		end
	end
end)

test("nodes use every prop variant", function()
	local used = {}
	for _, n in ipairs(WorldGen.generate(Config, 2).nodes) do
		used[n.kind .. n.variant] = true
	end
	for v = 1, Config.props.variants do
		assertTrue(used["tree" .. v] and used["rock" .. v], "variant " .. v .. " used by trees and rocks")
	end
end)

test("the spawn clearing at the world centre is open grass", function()
	local world = WorldGen.generate(Config, 4)
	local cx, cy = math.floor(world.width / 2), math.floor(world.height / 2)
	for y = cy - 3, cy + 3 do
		for x = cx - 3, cx + 3 do
			assertFalse(World.isBlocked(world, x, y), string.format("tile %d,%d open", x, y))
		end
	end
end)

test("a session over a generated world holds its nodes in the node pool", function()
	local Session = require("src.game.session")
	local world = WorldGen.generate(Config, 5)
	local ctx = Session.new(world, Config, 5)
	assertEqual(world.nodes, ctx.pools.nodes)
	assertEqual(0, #Session.new({ width = 4, height = 4 }, Config, 1).pools.nodes, "a literal world has no nodes")
end)
