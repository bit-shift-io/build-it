-- A hard-coded test house: proves the baker and world drawing until player
-- designs exist. A 3x2-tile footprint at 4 studs per tile, walls flush on
-- the footprint, a gable roof of slopes, and asymmetric details (door and
-- windows on the south face, a chimney at the north-east) so every facing
-- looks different. Pure -- no `love.*`.
local Model = require("src.game.blocks.model")

local TestHouse = {}

local WALL = { 0.93, 0.86, 0.7 }
local DOOR = { 0.45, 0.3, 0.18 }
local WINDOW = { 0.45, 0.65, 0.85 }
local ROOF = { 0.72, 0.25, 0.2 }
local CHIMNEY = { 0.5, 0.5, 0.52 }

local STUDS_PER_TILE = 4
local WIDTH, DEPTH = 3, 2 -- tiles
local WALL_HEIGHT = 6 -- studs

function TestHouse.model()
	local w, d = WIDTH * STUDS_PER_TILE, DEPTH * STUDS_PER_TILE
	-- Later cells replace earlier ones at the same position.
	local grid, order = {}, {}
	local function put(x, y, z, cell)
		local k = x .. "," .. y .. "," .. z
		if not grid[k] then
			table.insert(order, k)
		end
		cell.x, cell.y, cell.z = x, y, z
		grid[k] = cell
	end

	for z = 0, WALL_HEIGHT - 1 do
		for y = 0, d - 1 do
			for x = 0, w - 1 do
				put(x, y, z, { color = WALL })
			end
		end
	end
	for z = 0, 2 do
		put(2, d - 1, z, { color = DOOR })
		put(3, d - 1, z, { color = DOOR })
	end
	for z = 2, 3 do
		for _, x in ipairs({ 6, 7, 9, 10 }) do
			put(x, d - 1, z, { color = WINDOW })
		end
		put(w - 1, 3, z, { color = WINDOW })
		put(w - 1, 4, z, { color = WINDOW })
	end

	-- Gable roof: each layer steps in one row from the north and south eaves.
	for layer = 0, d / 2 - 1 do
		local z = WALL_HEIGHT + layer
		for x = 0, w - 1 do
			put(x, layer, z, { shape = "slope", dir = "N", color = ROOF })
			put(x, d - 1 - layer, z, { shape = "slope", dir = "S", color = ROOF })
			for y = layer + 1, d - 2 - layer do
				put(x, y, z, { color = WALL })
			end
		end
	end

	for z = WALL_HEIGHT, WALL_HEIGHT + d / 2 + 1 do
		for y = 1, 2 do
			for x = w - 3, w - 2 do
				put(x, y, z, { color = CHIMNEY })
			end
		end
	end

	local m = Model.new(STUDS_PER_TILE, WIDTH, DEPTH)
	for _, k in ipairs(order) do
		Model.addCell(m, grid[k])
	end
	return m
end

-- Where the world shows the test house: one per facing in a row west to
-- east, offset from the world's centre tile by config.testHouses.
--   { { facing, tileX, tileY }, ... }  (tileX, tileY: footprint north-west corner)
function TestHouse.placements(world, config)
	local cfg = config.testHouses
	local cx, cy = math.floor(world.width / 2), math.floor(world.height / 2)
	local out = {}
	for i, facing in ipairs(Model.FACINGS) do
		out[i] = { facing = facing, tileX = cx + cfg.offsetX + (i - 1) * cfg.spacing, tileY = cy + cfg.offsetY }
	end
	return out
end

return TestHouse
