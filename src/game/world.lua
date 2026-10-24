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
local WalkGrid = require("src.game.buildings.walk_grid")

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
-- clamps to the world edge. Footprints are solid: whoever walks into a
-- building walks by its stud cells instead (World.studBlocker,
-- World.doorways).
function World.isBlocked(world, x, y)
	if World.terrainAt(world, x, y) == "water" or World.nodeAt(world, x, y) ~= nil then
		return true
	end
	return World.buildingAt(world, x, y) ~= nil
end

-- What blocks stud cell (sx, sy) (docs/CONTEXT.md "Walk grid"; `per` cells a
-- tile side, 0-based from the world's north-west) for a record that walks
-- into finished buildings: nil when nothing does, else the blocker -- the
-- building whose footprint covers it, or the tile index of water or a node.
-- gridOf(building) is the building's walk grid turned to its facing, nil
-- when the record may not walk in (a construction site): then the whole
-- footprint blocks, otherwise only its blocked cells.
function World.studBlocker(world, sx, sy, per, gridOf)
	local tx, ty = math.floor(sx / per), math.floor(sy / per)
	if World.terrainAt(world, tx, ty) == "water" or World.nodeAt(world, tx, ty) ~= nil then
		return ty * world.width + tx
	end
	local b = World.buildingAt(world, tx, ty)
	if b == nil then
		return nil
	end
	local grid = gridOf(b)
	if grid == nil or not WalkGrid.open(grid, sx - b.tileX * per, sy - b.tileY * per) then
		return b
	end
	return nil
end

-- The doorways of building b (docs/CONTEXT.md "Doorway"), whose walk grid
-- turned to its facing is `grid`, `per` cells a tile side: every open cell
-- on the footprint's edge with an open tile (World.isBlocked; port tiles
-- count) just outside it, as
--   { tileX, tileY,   -- that outside tile
--     cellX, cellY,   -- the edge cell, 0-based on the grid
--     outX, outY }    -- the cell across the edge from it, one off the grid
-- North edge west to east, then the east, south and west edges.
function World.doorways(world, b, grid, per)
	local list = {}
	local function try(cx, cy, ox, oy)
		local tx, ty = b.tileX + math.floor(ox / per), b.tileY + math.floor(oy / per)
		if WalkGrid.open(grid, cx, cy) and index(world, tx, ty) and not World.isBlocked(world, tx, ty) then
			list[#list + 1] = { tileX = tx, tileY = ty, cellX = cx, cellY = cy, outX = ox, outY = oy }
		end
	end
	local w, d = grid.width, grid.depth
	for x = 0, w - 1 do
		try(x, 0, x, -1)
	end
	for y = 0, d - 1 do
		try(w - 1, y, w, y)
	end
	for x = 0, w - 1 do
		try(x, d - 1, x, d)
	end
	for y = 0, d - 1 do
		try(0, y, -1, y)
	end
	return list
end

-- True when a villager may stand still on tile (x, y): inside the world,
-- not blocked with footprints solid, and not a port tile.
function World.isStandable(world, x, y)
	return x >= 0
		and y >= 0
		and x < world.width
		and y < world.height
		and not World.isBlocked(world, x, y)
		and World.portAt(world, x, y) == nil
end

-- The standable tile touching building b's footprint (corners included)
-- nearest tile (x, y); ties go to the first in row order. Nil when the
-- footprint is walled in. Where villagers stand to work on a site, since
-- nobody walks onto one.
function World.tileBeside(world, b, x, y)
	local best, bestD
	for ty = b.tileY - 1, b.tileY + b.depth do
		for tx = b.tileX - 1, b.tileX + b.width do
			local inside = tx >= b.tileX and tx < b.tileX + b.width and ty >= b.tileY and ty < b.tileY + b.depth
			if not inside and World.isStandable(world, tx, ty) then
				local d = (tx - x) ^ 2 + (ty - y) ^ 2
				if not bestD or d < bestD then
					best, bestD = { tx, ty }, d
				end
			end
		end
	end
	if best then
		return best[1], best[2]
	end
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
