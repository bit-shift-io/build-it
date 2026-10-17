-- Mover component: walks a record across the world from a move intent.
-- Plain data on the record (`record.mover = { speed = <px/s>, enter = <building>
-- | nil }`; enter is the one footprint the record may walk into); the owning
-- pool system calls Mover.apply. Never runs itself (docs/ARCHITECTURE.md
-- "Component").
local Vec2 = require("src.core.vec2")
local World = require("src.game.world")

local Mover = {}

local function clamp(v, lo, hi)
	return math.max(lo, math.min(hi, v))
end

-- What blocks the square of side 2 * half centred on (x, y): a set of
-- blockers, one per blocked tile (World.isBlocked, footprints open for
-- `enter`) -- a footprint tile counts as its whole building. Touching a
-- tile's edge is not overlapping.
local function blockersAt(world, tile, x, y, half, enter)
	local set = {}
	for ty = math.floor((y - half) / tile), math.ceil((y + half) / tile) - 1 do
		for tx = math.floor((x - half) / tile), math.ceil((x + half) / tile) - 1 do
			if World.isBlocked(world, tx, ty, enter) then
				set[World.buildingAt(world, tx, ty) or (ty * world.width + tx)] = true
			end
		end
	end
	return set
end

-- True when every blocker in `set` is also in `base`.
local function within(set, base)
	for id in pairs(set) do
		if not base[id] then
			return false
		end
	end
	return true
end

-- Moves one axis from `from` to `to`, stopping flush against the first
-- blocked tile in the way. One step never crosses more than one tile edge
-- (speed * dt is far below a tile). A record already overlapping a blocker
-- keeps moving as long as it adds none, so it can walk out of a footprint
-- but never into another.
local function moveAxis(from, to, half, tile, blockersAtPos)
	if to == from then
		return to
	end
	local atTo = blockersAtPos(to)
	if next(atTo) == nil or within(atTo, blockersAtPos(from)) then
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
-- along a shore. Building footprints stop it too, except the one building in
-- record.mover.enter (an operator inside its own building). A record that
-- already overlaps a footprint may move out of it, not into another.
function Mover.apply(record, intent, ctx)
	local dir = Vec2.normalize(intent)
	local step = record.mover.speed * ctx.dt
	local half = record.size / 2
	local tile = ctx.config.tileSize
	local world = ctx.world
	local w, h = World.pixelSize(world, ctx.config)
	local enter = record.mover.enter

	local toX = clamp(record.x + dir.x * step, half, w - half)
	record.x = moveAxis(record.x, toX, half, tile, function(x)
		return blockersAt(world, tile, x, record.y, half, enter)
	end)
	local toY = clamp(record.y + dir.y * step, half, h - half)
	record.y = moveAxis(record.y, toY, half, tile, function(y)
		return blockersAt(world, tile, record.x, y, half, enter)
	end)
end

return Mover
