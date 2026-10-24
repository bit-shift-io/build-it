-- A blueprint's walk grid (docs/CONTEXT.md "Walk grid", "Doorway", ADR
-- 0008): its footprint in stud cells, config.walk.cellsPerTile a tile
-- side, each open or blocked. Comes from geometry only. Pure; plain LuaJIT.
--
--   { width, depth,   -- in cells
--     cells }         -- a string, one character a cell, row by row from
--                     -- the north-west: "." open, "x" blocked
--
-- Cell (x, y), 0-based, covers model space [x, x + 1) / cellsPerTile east
-- and [y, y + 1) / cellsPerTile south.
local WalkGrid = {}

local OPEN, BLOCKED = ".", "x"

-- The walk grid of a `width` x `depth` tile footprint holding voxels whose
-- centres are `centres` ({ { x, y, z }, ... }, model space in tiles): a
-- cell blocks when a centre over it lies at or above walk.floorClearance
-- and below walk.bodyHeight (config.walk).
function WalkGrid.of(centres, width, depth, walk)
	local per = walk.cellsPerTile
	local w, d = width * per, depth * per
	local blocked = {}
	for _, v in ipairs(centres) do
		if v.z >= walk.floorClearance and v.z < walk.bodyHeight then
			local x = math.max(0, math.min(w - 1, math.floor(v.x * per)))
			local y = math.max(0, math.min(d - 1, math.floor(v.y * per)))
			blocked[y * w + x] = true
		end
	end
	local cells = {}
	for i = 0, w * d - 1 do
		cells[i + 1] = blocked[i] and BLOCKED or OPEN
	end
	return { width = w, depth = d, cells = table.concat(cells) }
end

-- Whether cell (x, y) of `grid` is open; false off the grid.
function WalkGrid.open(grid, x, y)
	if x < 0 or y < 0 or x >= grid.width or y >= grid.depth then
		return false
	end
	local i = y * grid.width + x + 1
	return grid.cells:sub(i, i) == OPEN
end

-- `grid` turned `turns` quarters clockwise seen from above, as Placement
-- turns footprints: cell (x, y) of a w x d grid going to (d - 1 - y, x)
-- each quarter. A new grid.
function WalkGrid.turn(grid, turns)
	for _ = 1, turns % 4 do
		local w, d = grid.width, grid.depth
		local cells = {}
		for y = 0, d - 1 do
			for x = 0, w - 1 do
				local i = y * w + x + 1
				cells[x * d + (d - 1 - y) + 1] = grid.cells:sub(i, i)
			end
		end
		grid = { width = d, depth = w, cells = table.concat(cells) }
	end
	return grid
end

-- The open cells of `grid` reached, side to side, from the open cells in
-- `seeds` ({ { x, y }, ... }, 0-based). { [y * width + x] = true }.
-- Stepping side to side reaches the same cells as 8 ways without cutting
-- corners (Pathfind.studs).
function WalkGrid.reached(grid, seeds)
	local w = grid.width
	local reached, queue = {}, {}
	local function visit(x, y)
		local i = y * w + x
		if not reached[i] and WalkGrid.open(grid, x, y) then
			reached[i] = true
			queue[#queue + 1] = i
		end
	end
	for _, s in ipairs(seeds) do
		visit(s[1], s[2])
	end
	local head = 1
	while queue[head] do
		local i = queue[head]
		head = head + 1
		local x, y = i % w, math.floor(i / w)
		visit(x + 1, y)
		visit(x - 1, y)
		visit(x, y + 1)
		visit(x, y - 1)
	end
	return reached
end

-- The open cells of `grid` reached from outside: flooded from every open
-- cell on the footprint's edge.
local function outside(grid)
	local w, d = grid.width, grid.depth
	local seeds = {}
	for x = 0, w - 1 do
		seeds[#seeds + 1] = { x, 0 }
		seeds[#seeds + 1] = { x, d - 1 }
	end
	for y = 0, d - 1 do
		seeds[#seeds + 1] = { 0, y }
		seeds[#seeds + 1] = { w - 1, y }
	end
	return WalkGrid.reached(grid, seeds)
end

-- Whether a figure from outside the footprint can walk up to `area`
-- ({ minX, minY, maxX, maxY }, model space in tiles; a function brick's
-- ground): some open cell reached from the footprint's edge lies on or
-- beside (8-neighbouring) the cells under it. `per` is cells a tile side.
function WalkGrid.reaches(grid, area, per)
	local reached = outside(grid)
	local x0 = math.floor(area.minX * per) - 1
	local y0 = math.floor(area.minY * per) - 1
	local x1 = math.max(x0 + 1, math.ceil(area.maxX * per) - 1) + 1
	local y1 = math.max(y0 + 1, math.ceil(area.maxY * per) - 1) + 1
	for y = math.max(0, y0), math.min(grid.depth - 1, y1) do
		for x = math.max(0, x0), math.min(grid.width - 1, x1) do
			if reached[y * grid.width + x] then
				return true
			end
		end
	end
	return false
end

return WalkGrid
