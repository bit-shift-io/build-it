-- The flat tile world. A world table is plain data:
--   { width = <tiles>, height = <tiles>,
--     terrain = { [index] = "grass"|"water" },   -- optional, all grass when nil
--     nodes = { <node>, ... },                   -- optional, the node pool
--     nodeAt = { [index] = <node> },             -- optional, nodes by tile
--     buildingAt = { [index] = <building> },     -- optional, footprint tiles
--     portAt = { [index] = <port> } }            -- optional, port tiles
-- index = y * width + x + 1 for tile (x, y), 0-based. A literal
-- { width, height } table is a valid all-grass, empty world.
--
-- A resource node (docs/CONTEXT.md "Resource node"):
--   { id, kind = "tree"|"rock", tileX, tileY, variant, stage, amount }
--
-- Tile size in pixels comes from config.tileSize, so the world itself holds
-- no tuning numbers. Pure -- no `love.*` (docs/ARCHITECTURE.md "Layers").
local World = {}

-- An all-grass world with an empty node pool.
function World.new(width, height)
	local world = { width = width, height = height, terrain = {}, nodes = {}, nodeAt = {} }
	for i = 1, width * height do
		world.terrain[i] = "grass"
	end
	return world
end

local function index(world, x, y)
	if x < 0 or y < 0 or x >= world.width or y >= world.height then
		return nil
	end
	return y * world.width + x + 1
end

-- The terrain of tile (x, y); "grass" off a world with no terrain.
function World.terrainAt(world, x, y)
	local i = index(world, x, y)
	return (i and world.terrain and world.terrain[i]) or "grass"
end

function World.setTerrain(world, x, y, terrain)
	world.terrain[assert(index(world, x, y), "tile outside the world")] = terrain
end

-- The node on tile (x, y), or nil.
function World.nodeAt(world, x, y)
	local i = index(world, x, y)
	return i and world.nodeAt and world.nodeAt[i] or nil
end

-- Adds a node to the pool on its tile (node.tileX, node.tileY).
function World.addNode(world, node)
	local i = assert(index(world, node.tileX, node.tileY), "node outside the world")
	assert(not world.nodeAt[i], "tile already has a node")
	table.insert(world.nodes, node)
	world.nodeAt[i] = node
	return node
end

-- Removes a node from the pool and clears its tile, so the tile unblocks.
function World.removeNode(world, node)
	local i = assert(index(world, node.tileX, node.tileY), "node outside the world")
	if world.nodeAt[i] == node then
		world.nodeAt[i] = nil
	end
	for k, n in ipairs(world.nodes) do
		if n == node then
			table.remove(world.nodes, k)
			return
		end
	end
end

-- The building whose footprint covers tile (x, y), or nil.
function World.buildingAt(world, x, y)
	local i = index(world, x, y)
	return i and world.buildingAt and world.buildingAt[i] or nil
end

-- The building port facing tile (x, y), or nil.
function World.portAt(world, x, y)
	local i = index(world, x, y)
	return i and world.portAt and world.portAt[i] or nil
end

-- Marks a building's footprint tiles and its port tiles
-- (src/game/buildings/building.lua). The footprint must lie in the world.
function World.addBuilding(world, building)
	world.buildingAt = world.buildingAt or {}
	world.portAt = world.portAt or {}
	for y = building.tileY, building.tileY + building.depth - 1 do
		for x = building.tileX, building.tileX + building.width - 1 do
			world.buildingAt[assert(index(world, x, y), "building outside the world")] = building
		end
	end
	for _, port in ipairs(building.ports) do
		local i = index(world, port.x, port.y)
		if i then
			world.portAt[i] = port
		end
	end
end

-- Clears a building's footprint and port tiles (the ones still its own).
function World.removeBuilding(world, building)
	for y = building.tileY, building.tileY + building.depth - 1 do
		for x = building.tileX, building.tileX + building.width - 1 do
			local i = index(world, x, y)
			if world.buildingAt[i] == building then
				world.buildingAt[i] = nil
			end
		end
	end
	for _, port in ipairs(building.ports) do
		local i = index(world, port.x, port.y)
		if i and world.portAt[i] == port then
			world.portAt[i] = nil
		end
	end
end

-- True when nothing may stand on tile (x, y): water, a node or a building.
-- Port tiles stay open. Tiles off the world are not blocked here; Mover
-- clamps to the world edge.
function World.isBlocked(world, x, y)
	return World.terrainAt(world, x, y) == "water" or World.nodeAt(world, x, y) ~= nil or World.buildingAt(world, x, y) ~= nil
end

-- The world's size in pixels.
function World.pixelSize(world, config)
	return world.width * config.tileSize, world.height * config.tileSize
end

-- The pixel position of the world's centre.
function World.center(world, config)
	local w, h = World.pixelSize(world, config)
	return w / 2, h / 2
end

return World
