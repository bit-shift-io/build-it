-- The A* tile pathfinder (src/game/pathfind.lua): 8-way paths that go
-- around water and nodes, never cut a blocked corner, and cross building
-- footprints, except the one building a caller may enter (and the one it
-- starts inside, to walk out).
local Pathfind = require("src.game.pathfind")
local World = require("src.game.world")

local function onPath(path, x, y)
	for _, p in ipairs(path) do
		if p.x == x and p.y == y then
			return true
		end
	end
	return false
end

test("Pathfind.find walks straight across open grass to the target, start excluded", function()
	local path = Pathfind.find(World.new(10, 10), 1, 1, 4, 1)
	assertEqual(3, #path)
	assertEqual(2, path[1].x)
	assertEqual(4, path[3].x)
	assertEqual(1, path[3].y)
end)

test("Pathfind.find goes around a water wall and a node, never onto them", function()
	local world = World.new(10, 10)
	for y = 0, 7 do
		World.setTerrain(world, 4, y, "water")
	end
	World.addNode(world, { id = 1, kind = "tree", tileX = 5, tileY = 8, variant = 1, stage = 1, amount = 10 })
	local path = Pathfind.find(world, 1, 1, 8, 1)
	assertTrue(path ~= nil, "expected a route around the wall")
	for _, p in ipairs(path) do
		assertFalse(World.isBlocked(world, p.x, p.y), "path crosses blocked tile " .. p.x .. "," .. p.y)
	end
	assertTrue(onPath(path, 4, 8) or onPath(path, 4, 9), "the path rounds the wall's south end")
	assertEqual(8, path[#path].x)
	assertEqual(1, path[#path].y)
end)

test("Pathfind.find never cuts the corner of a blocked tile", function()
	local world = World.new(5, 5)
	World.setTerrain(world, 2, 1, "water")
	-- (1, 1) to (2, 2) diagonally would clip the water at (2, 1).
	local path = Pathfind.find(world, 1, 1, 2, 2)
	assertEqual(2, #path)
	assertEqual(1, path[1].x)
	assertEqual(2, path[1].y)
end)

test("Pathfind.find returns nil when water walls the target off, or the target is blocked", function()
	local world = World.new(10, 10)
	for y = 0, 9 do
		World.setTerrain(world, 4, y, "water")
	end
	assertEqual(nil, Pathfind.find(world, 1, 1, 8, 1))
	assertEqual(nil, Pathfind.find(world, 1, 1, 4, 1))
	assertEqual(nil, Pathfind.find(world, 1, 1, 10, 1))
end)

test("Pathfind.find gives up after maxExpansions tiles", function()
	local world = World.new(128, 128)
	for y = 0, 127 do
		World.setTerrain(world, 100, y, "water")
	end
	assertEqual(nil, Pathfind.find(world, 1, 1, 120, 1, { maxExpansions = 50 }))
	assertTrue(Pathfind.find(world, 1, 1, 10, 1, { maxExpansions = 50 }) ~= nil, "a near target is still found")
end)

local function footprintWorld()
	local world = World.new(10, 5)
	-- A 1-wide building wall from top to bottom at x = 4.
	World.addBuilding(world, { tileX = 4, tileY = 0, width = 1, depth = 5, ports = {} })
	return world
end

test("Pathfind.find goes around a footprint, and through the one building in opts.enter", function()
	local world = World.new(10, 5)
	-- A 1-wide building wall at x = 4 with a gap only at y = 4.
	local wall = { tileX = 4, tileY = 0, width = 1, depth = 4, ports = {} }
	World.addBuilding(world, wall)
	local around = Pathfind.find(world, 1, 2, 8, 2)
	assertTrue(around ~= nil and onPath(around, 4, 4) and not onPath(around, 4, 2), "expected a route round the wall")
	local through = Pathfind.find(world, 1, 2, 8, 2, { enter = wall })
	assertTrue(through ~= nil and onPath(through, 4, 2), "expected a straight route through the footprint")
	assertEqual(7, #through)
end)

test("Pathfind.find with enter = a building still stops at any other footprint", function()
	local world = World.new(10, 5)
	local mine = { tileX = 2, tileY = 0, width = 1, depth = 5, ports = {} }
	local other = { tileX = 5, tileY = 0, width = 1, depth = 5, ports = {} }
	World.addBuilding(world, mine)
	World.addBuilding(world, other)
	assertTrue(Pathfind.find(world, 0, 2, 3, 2, { enter = mine }) ~= nil)
	assertEqual(nil, Pathfind.find(world, 0, 2, 8, 2, { enter = mine }))
	assertEqual(nil, Pathfind.find(world, 0, 2, 5, 2, { enter = mine }), "the target may not be another footprint")
end)

test("Pathfind.find lets a walker that starts inside a footprint walk out of it", function()
	local world = World.new(10, 10)
	World.addBuilding(world, { tileX = 3, tileY = 3, width = 3, depth = 3, ports = {} })
	-- The centre tile has only footprint tiles around it.
	local path = Pathfind.find(world, 4, 4, 8, 4)
	assertTrue(path ~= nil, "expected a way out")
	assertEqual(8, path[#path].x)
end)

test("Pathfind.find gives the same path for the same input", function()
	local function route()
		local world = World.new(20, 20)
		for x = 3, 15 do
			World.setTerrain(world, x, 10, "water")
		end
		return Pathfind.find(world, 9, 2, 9, 18)
	end
	local a, b = route(), route()
	assertEqual(#a, #b)
	for i = 1, #a do
		assertEqual(a[i].x, b[i].x)
		assertEqual(a[i].y, b[i].y)
	end
end)
