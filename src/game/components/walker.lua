-- Walker component: follows a tile path (src/game/pathfind.lua), steering
-- through Mover one tile centre at a time. Plain data on the record
-- (`record.walker`); the owning pool system calls Walker.step. Pure.
--   walker = { path = { { x, y }, ... },   -- tiles still to reach, next first
--              failed = true | nil }        -- the walk lost its route (Walker.failed)
-- The record needs `mover` (and its `enter` building, if any, picks the paths).
local Mover = require("src.game.components.mover")
local Pathfind = require("src.game.pathfind")
local World = require("src.game.world")

local Walker = {}

function Walker.new()
	return { path = {} }
end

-- True when the walker has no tiles left to reach.
function Walker.idle(walker)
	return #walker.path == 0
end

-- Sends `record` to tile (tileX, tileY) from the tile it stands on. Finds
-- the path once, here, never per step. Returns false and stands still when
-- there is no route within config.villagers.pathMaxExpansions.
function Walker.goTo(record, ctx, tileX, tileY)
	local tile = ctx.config.tileSize
	local path = Pathfind.find(ctx.world, math.floor(record.x / tile), math.floor(record.y / tile), tileX, tileY, {
		enter = record.mover.enter,
		maxExpansions = ctx.config.villagers.pathMaxExpansions,
	})
	record.walker.path = path or {}
	record.walker.failed = nil
	return path ~= nil
end

-- True when the walk was cut off: the path crossed a footprint placed after
-- it was found and no other route exists. The walker stands still; a job
-- must end rather than count this as arrived. Cleared by the next goTo.
function Walker.failed(walker)
	return walker.failed == true
end

-- Whether tile (x, y) stops a walk from tile (fromX, fromY): the same rule
-- Pathfind.find uses (the footprint the walker stands in is open).
local function stops(record, ctx, x, y, fromX, fromY)
	local world = ctx.world
	if not World.isBlocked(world, x, y, record.mover.enter) then
		return false
	end
	local startIn = World.buildingAt(world, fromX, fromY)
	return not (startIn ~= nil and not World.isBlocked(world, x, y, startIn))
end

-- Walks toward the next tile's centre. Within one step of it, lands on the
-- centre and moves on to the tile after, so the walk ends exactly on the
-- target's centre.
function Walker.step(record, ctx)
	local path = record.walker.path
	local nextTile = path[1]
	if not nextTile then
		return
	end
	local tile = ctx.config.tileSize
	if stops(record, ctx, nextTile.x, nextTile.y, math.floor(record.x / tile), math.floor(record.y / tile)) then
		local last = path[#path]
		if not Walker.goTo(record, ctx, last.x, last.y) then
			record.walker.failed = true
		end
		return
	end
	local dx, dy = (nextTile.x + 0.5) * tile - record.x, (nextTile.y + 0.5) * tile - record.y
	local d = math.sqrt(dx * dx + dy * dy)
	if d <= record.mover.speed * ctx.dt then
		record.x, record.y = (nextTile.x + 0.5) * tile, (nextTile.y + 0.5) * tile
		table.remove(path, 1)
		return
	end
	Mover.apply(record, { x = dx / d, y = dy / d }, ctx)
end

return Walker
