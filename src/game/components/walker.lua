-- Walker component: follows a tile path (src/game/pathfind.lua), steering
-- through Mover one tile centre at a time. Plain data on the record
-- (`record.walker`); the owning pool system calls Walker.step. Pure.
--   walker = { path = { { x, y }, ... } }   -- tiles still to reach, next first
-- The record needs `mover` (and its throughBuildings flag picks the paths).
local Mover = require("src.game.components.mover")
local Pathfind = require("src.game.pathfind")

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
		throughBuildings = record.mover.throughBuildings,
		maxExpansions = ctx.config.villagers.pathMaxExpansions,
	})
	record.walker.path = path or {}
	return path ~= nil
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
