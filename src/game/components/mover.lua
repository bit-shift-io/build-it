-- Mover component: walks a record across the world from a move intent.
-- Plain data on the record (`record.mover = { speed = <px/s> }`); the owning
-- pool system calls Mover.apply. Never runs itself (docs/ARCHITECTURE.md
-- "Component").
local Vec2 = require("src.core.vec2")
local World = require("src.game.world")

local Mover = {}

local function clamp(v, lo, hi)
	return math.max(lo, math.min(hi, v))
end

-- True when the square of side 2 * half centred on (x, y) overlaps a blocked
-- tile (World.isBlocked). Touching a tile's edge is not overlapping.
local function overlapsBlocked(world, tile, x, y, half)
	for ty = math.floor((y - half) / tile), math.ceil((y + half) / tile) - 1 do
		for tx = math.floor((x - half) / tile), math.ceil((x + half) / tile) - 1 do
			if World.isBlocked(world, tx, ty) then
				return true
			end
		end
	end
	return false
end

-- Moves one axis from `from` to `to`, stopping flush against the first
-- blocked tile in the way. One step never crosses more than one tile edge
-- (speed * dt is far below a tile). A record already overlapping a blocked
-- tile moves freely, so it can walk out.
local function moveAxis(from, to, half, tile, blockedAt)
	if to == from or not blockedAt(to) or blockedAt(from) then
		return to
	end
	if to > from then
		return math.floor((to + half) / tile) * tile - half
	end
	return math.ceil((to - half) / tile) * tile + half
end

-- intent = { x, y }, each in [-1, 1]. Diagonals are normalized so walking
-- diagonally is no faster than walking straight. The world edge stops the
-- record with its whole square still inside the world; water and resource
-- nodes stop it flush against their tile, each axis on its own so it slides
-- along a shore.
function Mover.apply(record, intent, ctx)
	local dir = Vec2.normalize(intent)
	local step = record.mover.speed * ctx.dt
	local half = record.size / 2
	local tile = ctx.config.tileSize
	local world = ctx.world
	local w, h = World.pixelSize(world, ctx.config)

	local toX = clamp(record.x + dir.x * step, half, w - half)
	record.x = moveAxis(record.x, toX, half, tile, function(x)
		return overlapsBlocked(world, tile, x, record.y, half)
	end)
	local toY = clamp(record.y + dir.y * step, half, h - half)
	record.y = moveAxis(record.y, toY, half, tile, function(y)
		return overlapsBlocked(world, tile, record.x, y, half)
	end)
end

return Mover
