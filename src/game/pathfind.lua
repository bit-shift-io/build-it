-- A* over the tile grid (docs/CONTEXT.md "Tile"). 8-way: a straight step
-- costs 10, a diagonal 14, and a diagonal never cuts a corner -- both tiles
-- beside it must be open too. Blocked tiles are World.isBlocked's: water,
-- nodes and building footprints. The same search runs over one building's
-- walk grid at stud resolution (Pathfind.studs).
-- Deterministic: open tiles leave the heap by cost, then by the heuristic,
-- then in the order they were first reached, and neighbours are tried in a
-- fixed order. Pure -- no `love.*`.
local World = require("src.game.world")
local WalkGrid = require("src.game.buildings.walk_grid")

local Pathfind = {}

local STRAIGHT, DIAGONAL = 10, 14

-- N, E, S, W, then NE, SE, SW, NW.
local STEPS = {
	{ 0, -1 },
	{ 1, 0 },
	{ 0, 1 },
	{ -1, 0 },
	{ 1, -1 },
	{ 1, 1 },
	{ -1, 1 },
	{ -1, -1 },
}

-- Octile distance in step costs: the exact cost on open ground.
local function heuristic(x, y, toX, toY)
	local dx, dy = math.abs(toX - x), math.abs(toY - y)
	return STRAIGHT * math.max(dx, dy) + (DIAGONAL - STRAIGHT) * math.min(dx, dy)
end

local function before(a, b)
	if a.f ~= b.f then
		return a.f < b.f
	end
	if a.h ~= b.h then
		return a.h < b.h
	end
	return a.order < b.order
end

local function push(heap, e)
	heap[#heap + 1] = e
	local i = #heap
	while i > 1 do
		local parent = math.floor(i / 2)
		if not before(heap[i], heap[parent]) then
			break
		end
		heap[i], heap[parent] = heap[parent], heap[i]
		i = parent
	end
end

local function pop(heap)
	local top = heap[1]
	local n = #heap
	heap[1] = heap[n]
	heap[n] = nil
	n = n - 1
	local i = 1
	while true do
		local l, r, best = 2 * i, 2 * i + 1, i
		if l <= n and before(heap[l], heap[best]) then
			best = l
		end
		if r <= n and before(heap[r], heap[best]) then
			best = r
		end
		if best == i then
			return top
		end
		heap[i], heap[best] = heap[best], heap[i]
		i = best
	end
end

-- A* over a w x h grid of cells where open(x, y) says which may be
-- entered, from (fromX, fromY) to (toX, toY): the cells after the start,
-- target last, or nil when out of reach within maxExpansions cells taken
-- off the open list (unlimited when nil). The start is never tested.
local function search(w, open, fromX, fromY, toX, toY, maxExpansions)
	if not open(toX, toY) then
		return nil
	end
	local function key(x, y)
		return y * w + x
	end
	local best = { [key(fromX, fromY)] = 0 }
	local cameFrom = {}
	local closed = {}
	local heap, order = {}, 0
	push(heap, { x = fromX, y = fromY, g = 0, h = 0, f = 0, order = 0 })
	local expansions = 0
	while #heap > 0 do
		local e = pop(heap)
		local k = key(e.x, e.y)
		if not closed[k] then
			closed[k] = true
			if e.x == toX and e.y == toY then
				local path = {}
				while k ~= key(fromX, fromY) do
					table.insert(path, 1, { x = k % w, y = math.floor(k / w) })
					k = cameFrom[k]
				end
				return path
			end
			expansions = expansions + 1
			if maxExpansions and expansions > maxExpansions then
				return nil
			end
			for i, s in ipairs(STEPS) do
				local nx, ny = e.x + s[1], e.y + s[2]
				local diagonal = i > 4
				if open(nx, ny) and (not diagonal or (open(e.x + s[1], e.y) and open(e.x, e.y + s[2]))) then
					local nk = key(nx, ny)
					local g = e.g + (diagonal and DIAGONAL or STRAIGHT)
					if not closed[nk] and (not best[nk] or g < best[nk]) then
						best[nk] = g
						cameFrom[nk] = k
						order = order + 1
						local hh = heuristic(nx, ny, toX, toY)
						push(heap, { x = nx, y = ny, g = g, h = hh, f = g + hh, order = order })
					end
				end
			end
		end
	end
	return nil
end

-- The tiles from (fromX, fromY) to (toX, toY), start excluded and target
-- last, as { { x, y }, ... }; an empty list when already there. nil when
-- the target is blocked, off the world, or out of reach within
-- opts.maxExpansions tiles taken off the open list (unlimited when nil).
-- Every footprint is solid; the walk grid inside one is Pathfind.studs'.
-- The start tile may itself be blocked, so a walker can step out of one:
-- the footprint it starts in is open for the walk, so it can cross it to
-- the edge (a construction site, which has no walk grid).
-- opts = { maxExpansions = <n> }, optional.
function Pathfind.find(world, fromX, fromY, toX, toY, opts)
	opts = opts or {}
	local startIn = World.buildingAt(world, fromX, fromY)
	local w, h = world.width, world.height
	local function open(x, y)
		return x >= 0
			and y >= 0
			and x < w
			and y < h
			and (not World.isBlocked(world, x, y) or (startIn ~= nil and World.buildingAt(world, x, y) == startIn))
	end
	return search(w, open, fromX, fromY, toX, toY, opts.maxExpansions)
end

-- The stud cells of walk grid `grid` (src/game/buildings/walk_grid.lua)
-- from cell (fromX, fromY) to (toX, toY), 0-based on the grid, as for
-- Pathfind.find: start excluded, target last, nil when the target is
-- blocked or walled off. Only open cells of the one grid are entered,
-- so the walk stays inside its footprint. The search is capped at the
-- grid's cell count, never the tile search's pathMaxExpansions.
function Pathfind.studs(grid, fromX, fromY, toX, toY)
	local function open(x, y)
		return WalkGrid.open(grid, x, y)
	end
	return search(grid.width, open, fromX, fromY, toX, toY, grid.width * grid.depth)
end

return Pathfind
