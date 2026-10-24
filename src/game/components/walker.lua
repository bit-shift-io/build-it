-- Walker component: follows a path of waypoints (src/game/pathfind.lua),
-- steering through Mover one waypoint's centre at a time. Plain data on
-- the record (`record.walker`); the owning pool system calls Walker.step.
-- Pure.
--   walker = { path = { <waypoint>, ... },  -- still to reach, next first
--              failed = true | nil }        -- the walk lost its route (Walker.failed)
--   waypoint = { x, y }                     -- a tile
--            | { x, y, stud = true }        -- a stud cell, 0-based from the
--                                           -- world's north-west
-- A walk runs in legs (docs/CONTEXT.md "Walk grid", "Doorway"): stud cells
-- out through a doorway of the finished building the record starts in,
-- tiles across open ground, and stud cells in through a doorway of the
-- building it walks into. Stud legs assume a body no wider than a stud.
-- The record needs `mover`; its `enter` building lets its walls stop it.
local Mover = require("src.game.components.mover")
local Pathfind = require("src.game.pathfind")
local World = require("src.game.world")
local WalkGrid = require("src.game.buildings.walk_grid")

local Walker = {}

function Walker.new()
	return { path = {} }
end

-- True when the walker has no waypoints left to reach.
function Walker.idle(walker)
	return #walker.path == 0
end

-- The finished building whose footprint `record` stands on, and its walk
-- grid; nil when none.
local function standingIn(record, ctx)
	local tile = ctx.config.tileSize
	local b = World.buildingAt(ctx.world, math.floor(record.x / tile), math.floor(record.y / tile))
	local grid = b and Mover.gridOf(b)
	if grid then
		return b, grid
	end
end

-- Appends cells `cells` ({ { x, y }, ... }, 0-based on building b's walk
-- grid) to `path` as stud waypoints.
local function addCells(path, b, per, cells)
	for _, c in ipairs(cells) do
		path[#path + 1] = { x = b.tileX * per + c.x, y = b.tileY * per + c.y, stud = true }
	end
end

local function addTiles(path, tiles)
	for _, t in ipairs(tiles) do
		path[#path + 1] = { x = t.x, y = t.y }
	end
end

-- `doors` (World.doorways) nearest point (px, py) first, by their edge
-- cell's centre, in cells on the grid; ties keep doorway order.
local function nearestFirst(doors, px, py)
	local order = {}
	for i, door in ipairs(doors) do
		order[i] = { door = door, i = i, d = (door.cellX + 0.5 - px) ^ 2 + (door.cellY + 0.5 - py) ^ 2 }
	end
	table.sort(order, function(a, b)
		if a.d ~= b.d then
			return a.d < b.d
		end
		return a.i < b.i
	end)
	for i, o in ipairs(order) do
		order[i] = o.door
	end
	return order
end

-- The waypoints from where `record` stands to `goal`: a tile { x, y }, or
-- { building, cellX, cellY }, a cell on that building's walk grid. Nil
-- when there is no route. Out of the building it stands in by the doorway
-- nearest the goal, into the goal's building by the doorway nearest the
-- goal cell (docs/CONTEXT.md "Doorway").
local function plan(record, ctx, goal)
	local world, tile = ctx.world, ctx.config.tileSize
	local per = ctx.config.walk.cellsPerTile
	local stud = tile / per
	local opts = { maxExpansions = ctx.config.villagers.pathMaxExpansions }
	local path = {}
	local fromX, fromY = math.floor(record.x / tile), math.floor(record.y / tile)
	local inB, inGrid = standingIn(record, ctx)
	if inB then
		local cx, cy = math.floor(record.x / stud) - inB.tileX * per, math.floor(record.y / stud) - inB.tileY * per
		if goal.building == inB then
			local cells = Pathfind.studs(inGrid, cx, cy, goal.cellX, goal.cellY)
			if not cells then
				return nil
			end
			addCells(path, inB, per, cells)
			return path
		end
		local gx, gy
		if goal.building then
			gx = (goal.building.tileX - inB.tileX) * per + goal.cellX + 0.5
			gy = (goal.building.tileY - inB.tileY) * per + goal.cellY + 0.5
		else
			gx, gy = (goal.x - inB.tileX + 0.5) * per, (goal.y - inB.tileY + 0.5) * per
		end
		local out
		for _, door in ipairs(nearestFirst(World.doorways(world, inB, inGrid, per), gx, gy)) do
			local cells = Pathfind.studs(inGrid, cx, cy, door.cellX, door.cellY)
			if cells then
				addCells(path, inB, per, cells)
				addCells(path, inB, per, { { x = door.outX, y = door.outY } })
				path[#path + 1] = { x = door.tileX, y = door.tileY }
				out = door
				break
			end
		end
		if not out then
			return nil
		end
		fromX, fromY = out.tileX, out.tileY
	end
	if not goal.building then
		local tiles = Pathfind.find(world, fromX, fromY, goal.x, goal.y, opts)
		if not tiles then
			return nil
		end
		addTiles(path, tiles)
		return path
	end
	local b = goal.building
	local grid = Mover.gridOf(b)
	if not grid then
		return nil
	end
	local tilePaths = {} -- a doorway tile's route, false when none
	for _, door in ipairs(nearestFirst(World.doorways(world, b, grid, per), goal.cellX + 0.5, goal.cellY + 0.5)) do
		local cells = Pathfind.studs(grid, door.cellX, door.cellY, goal.cellX, goal.cellY)
		if cells then
			local k = door.tileY * world.width + door.tileX
			if tilePaths[k] == nil then
				tilePaths[k] = Pathfind.find(world, fromX, fromY, door.tileX, door.tileY, opts) or false
			end
			if tilePaths[k] then
				addTiles(path, tilePaths[k])
				addCells(path, b, per, { { x = door.outX, y = door.outY }, { x = door.cellX, y = door.cellY } })
				addCells(path, b, per, cells)
				return path
			end
		end
	end
	return nil
end

local function follow(record, path)
	record.walker.path = path or {}
	record.walker.failed = nil
	return path ~= nil
end

-- Sends `record` to tile (tileX, tileY), outside any footprint. Finds the
-- route once, here, never per step. Returns false and stands still when
-- there is none within config.villagers.pathMaxExpansions tiles a leg.
function Walker.goTo(record, ctx, tileX, tileY)
	return follow(record, plan(record, ctx, { x = tileX, y = tileY }))
end

-- Sends `record` into finished building b, through a doorway, to the open
-- cell of its walk grid nearest world point (px, py) (tiles, fractional;
-- a function brick's or bed's position) that a doorway reaches; ties go to
-- the first in row order. False, standing still, when there is none.
function Walker.goInside(record, ctx, b, px, py)
	local grid = Mover.gridOf(b)
	if not grid then
		return follow(record, nil)
	end
	local per = ctx.config.walk.cellsPerTile
	local seeds = {}
	for _, door in ipairs(World.doorways(ctx.world, b, grid, per)) do
		seeds[#seeds + 1] = { door.cellX, door.cellY }
	end
	local reached = WalkGrid.reached(grid, seeds)
	local lx, ly = (px - b.tileX) * per, (py - b.tileY) * per
	local best, bestD
	for y = 0, grid.depth - 1 do
		for x = 0, grid.width - 1 do
			if reached[y * grid.width + x] then
				local d = (x + 0.5 - lx) ^ 2 + (y + 0.5 - ly) ^ 2
				if not bestD or d < bestD then
					best, bestD = { x, y }, d
				end
			end
		end
	end
	if not best then
		return follow(record, nil)
	end
	return follow(record, plan(record, ctx, { building = b, cellX = best[1], cellY = best[2] }))
end

-- True when the walk was cut off: the path crossed a footprint placed after
-- it was found and no other route exists. The walker stands still; a job
-- must end rather than count this as arrived. Cleared by the next goTo.
function Walker.failed(walker)
	return walker.failed == true
end

-- Whether waypoint `wp` stops a walk now. A tile: as Pathfind.find has it
-- (the footprint the walker stands in is open). A stud cell: as
-- World.studBlocker has it through finished buildings' walk grids.
local function stops(record, ctx, wp)
	local world = ctx.world
	if wp.stud then
		return World.studBlocker(world, wp.x, wp.y, ctx.config.walk.cellsPerTile, Mover.gridOf) ~= nil
	end
	if not World.isBlocked(world, wp.x, wp.y) then
		return false
	end
	local tile = ctx.config.tileSize
	local startIn = World.buildingAt(world, math.floor(record.x / tile), math.floor(record.y / tile))
	return not (startIn ~= nil and World.buildingAt(world, wp.x, wp.y) == startIn)
end

-- The goal that waypoint `wp`, a path's last, stands for in plan; nil
-- when its building is gone.
local function goalOf(ctx, wp)
	if not wp.stud then
		return { x = wp.x, y = wp.y }
	end
	local per = ctx.config.walk.cellsPerTile
	local b = World.buildingAt(ctx.world, math.floor(wp.x / per), math.floor(wp.y / per))
	if b then
		return { building = b, cellX = wp.x - b.tileX * per, cellY = wp.y - b.tileY * per }
	end
end

-- The pixel centre of waypoint `wp`.
local function centre(ctx, wp)
	local size = ctx.config.tileSize
	if wp.stud then
		size = size / ctx.config.walk.cellsPerTile
	end
	return (wp.x + 0.5) * size, (wp.y + 0.5) * size
end

-- Walks toward the next waypoint's centre. Within one step of it, lands on
-- the centre and moves on to the one after, so the walk ends exactly on
-- the last one's centre and runs leg into leg without a stop. A waypoint
-- blocked since the route was found makes it find a new route to the last.
function Walker.step(record, ctx)
	local path = record.walker.path
	local wp = path[1]
	if not wp then
		return
	end
	if stops(record, ctx, wp) then
		local goal = goalOf(ctx, path[#path])
		if not follow(record, goal and plan(record, ctx, goal)) then
			record.walker.failed = true
		end
		return
	end
	local tx, ty = centre(ctx, wp)
	local dx, dy = tx - record.x, ty - record.y
	local d = math.sqrt(dx * dx + dy * dy)
	if d <= record.mover.speed * ctx.dt then
		record.x, record.y = tx, ty
		table.remove(path, 1)
		return
	end
	Mover.apply(record, { x = dx / d, y = dy / d }, ctx)
end

return Walker
