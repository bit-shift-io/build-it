-- Block model: plain data describing a 3D object as unit cells on a grid
-- (docs/CONTEXT.md "Block model"). The only input to the baker. Holds no
-- rendering state. Pure -- no `love.*`.
--
--   { cellsPerTile = 4, width = 2, depth = 1, cells = { <cell>, ... } }
--
-- Model space: x east, y south, z up, in cells. cellsPerTile is the grid
-- scale (4 for studs, 16 for voxels). width/depth are the footprint in
-- tiles; the footprint's north-west ground corner is the model origin.
--
-- A cell: { x, y, z, shape = "box"|"slope", dir = "N"|"E"|"S"|"W",
--           color = { r, g, b }, material = <optional string> }
-- A slope's dir is the way its sloped face looks: dir "S" is high on its
-- north edge and low on its south edge.
local Model = {}

function Model.new(cellsPerTile, width, depth)
	return { cellsPerTile = cellsPerTile, width = width or 1, depth = depth or 1, cells = {} }
end

-- Appends a cell (shape defaults to "box") and returns it.
function Model.addCell(model, cell)
	cell.shape = cell.shape or "box"
	table.insert(model.cells, cell)
	return cell
end

-- The box enclosing every cell, in cells, max exclusive. All zero when empty.
function Model.bounds(model)
	local cells = model.cells
	if #cells == 0 then
		return { minX = 0, minY = 0, minZ = 0, maxX = 0, maxY = 0, maxZ = 0 }
	end
	local b = { minX = math.huge, minY = math.huge, minZ = math.huge, maxX = -math.huge, maxY = -math.huge, maxZ = -math.huge }
	for _, c in ipairs(cells) do
		b.minX, b.maxX = math.min(b.minX, c.x), math.max(b.maxX, c.x + 1)
		b.minY, b.maxY = math.min(b.minY, c.y), math.max(b.maxY, c.y + 1)
		b.minZ, b.maxZ = math.min(b.minZ, c.z), math.max(b.maxZ, c.z + 1)
	end
	return b
end

-- The 4 facings in clockwise order. Facing N is the model as authored; each
-- step after it turns the model a quarter clockwise seen from above.
Model.FACINGS = { "N", "E", "S", "W" }

local QUARTER_TURNS = { N = 0, E = 1, S = 2, W = 3 }
local CLOCKWISE = { N = "E", E = "S", S = "W", W = "N" }

local function copyCell(c)
	local copy = {}
	for k, v in pairs(c) do
		copy[k] = v
	end
	return copy
end

-- A new model turned to `facing` about its footprint: cells stay inside the
-- footprint, the footprint swaps width and depth on E and W, and slope dirs
-- turn with the cells. The source model is untouched.
function Model.rotate(model, facing)
	local turns = assert(QUARTER_TURNS[facing], "unknown facing " .. tostring(facing))
	local out = Model.new(model.cellsPerTile, model.width, model.depth)
	for _, c in ipairs(model.cells) do
		table.insert(out.cells, copyCell(c))
	end
	for _ = 1, turns do
		-- (x, y) -> (depthCells - 1 - y, x): north edge becomes east edge.
		local depthCells = out.depth * out.cellsPerTile
		for _, c in ipairs(out.cells) do
			c.x, c.y = depthCells - 1 - c.y, c.x
			if c.dir then
				c.dir = CLOCKWISE[c.dir]
			end
		end
		out.width, out.depth = out.depth, out.width
	end
	return out
end

return Model
