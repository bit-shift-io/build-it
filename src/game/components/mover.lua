-- Mover component: walks a record across the world from a move intent.
-- Plain data on the record (`record.mover = { speed = <px/s>, enter = <building>
-- | nil, entersBuildings = true | nil }`): entersBuildings lets it walk into
-- any finished building through its walk grid (the player's); enter lets it
-- walk into that one finished building the same way, walls included (an
-- operator's or sleeper's own building). Every other footprint is solid.
-- The owning pool system calls Mover.apply. Never runs itself
-- (docs/ARCHITECTURE.md "Component").
local Vec2 = require("src.core.vec2")
local World = require("src.game.world")

local Mover = {}

local function clamp(v, lo, hi)
	return math.max(lo, math.min(hi, v))
end

-- What blocks the square of side 2 * half centred on (x, y): a set of
-- blockers, one per blocked tile (World.isBlocked) -- a footprint tile
-- counts as its whole building. Touching a tile's edge is not overlapping.
local function blockersAt(world, tile, x, y, half)
	local set = {}
	for ty = math.floor((y - half) / tile), math.ceil((y + half) / tile) - 1 do
		for tx = math.floor((x - half) / tile), math.ceil((x + half) / tile) - 1 do
			if World.isBlocked(world, tx, ty) then
				set[World.buildingAt(world, tx, ty) or (ty * world.width + tx)] = true
			end
		end
	end
	return set
end

-- Each building's walk grid turned to its facing, worked out once.
local grids = setmetatable({}, { __mode = "k" })

-- The walk grid of building `b` turned to its facing, what a record that
-- enters it walks by; nil for a construction site (its `cost` still to
-- build) or a footprint with no blueprint, which stay solid.
local function gridOf(b)
	if b.cost ~= nil or b.blueprint == nil then
		return nil
	end
	local grid = grids[b]
	if grid == nil then
		-- Required here, not at load: Placement reaches (through function
		-- bricks and their systems) modules that require Mover.
		grid = require("src.game.buildings.placement").walkGrid(b.blueprint, b.facing)
		grids[b] = grid
	end
	return grid
end

Mover.gridOf = gridOf

-- blockersAt for a record that enters buildings: blocked stud cells
-- (World.studBlocker, walk grids from `grids`) under the square, a
-- building's blocked cells all counting as that building, so a record
-- standing in a wall can walk out.
local function studBlockersAt(world, stud, per, x, y, half, grids)
	local set = {}
	for sy = math.floor((y - half) / stud), math.ceil((y + half) / stud) - 1 do
		for sx = math.floor((x - half) / stud), math.ceil((x + half) / stud) - 1 do
			local blocker = World.studBlocker(world, sx, sy, per, grids)
			if blocker ~= nil then
				set[blocker] = true
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
-- blocked cell in the way, `cell` px a side (a tile, or a stud for a record
-- that enters buildings). One step never crosses more than one cell edge:
-- speed * dt is under a stud (160 px/s at 60 fps is about 2.7 px of 8).
-- A record already overlapping a blocker keeps moving as long as it adds none, so it can walk out of a footprint
-- but never into another.
local function moveAxis(from, to, half, cell, blockersAtPos)
	if to == from then
		return to
	end
	local atTo = blockersAtPos(to)
	if next(atTo) == nil or within(atTo, blockersAtPos(from)) then
		return to
	end
	if to > from then
		return math.floor((to + half) / cell) * cell - half
	end
	return math.ceil((to - half) / cell) * cell + half
end

-- intent = { x, y }, each in [-1, 1]. Diagonals are normalized so walking
-- diagonally is no faster than walking straight. The world edge stops the
-- record with its whole square still inside the world; water and resource
-- nodes stop it flush against their tile, each axis on its own so it slides
-- along a shore. Building footprints stop it too. A record with
-- record.mover.entersBuildings walks into finished buildings instead, and
-- one with record.mover.enter into that one building, stopped by their
-- walls stud by stud; construction sites stay solid. A record that already
-- overlaps a footprint or wall may move out of it, not into another.
function Mover.apply(record, intent, ctx)
	local dir = Vec2.normalize(intent)
	local step = record.mover.speed * ctx.dt
	local half = record.size / 2
	local tile = ctx.config.tileSize
	local world = ctx.world
	local w, h = World.pixelSize(world, ctx.config)
	local enter = record.mover.enter

	local cell, at = tile, nil -- at(x, y): the blockers under the square there
	if record.mover.entersBuildings or enter then
		local per = ctx.config.walk.cellsPerTile
		local grids = gridOf
		if not record.mover.entersBuildings then
			grids = function(b)
				return b == enter and gridOf(b) or nil
			end
		end
		cell = tile / per
		at = function(x, y)
			return studBlockersAt(world, cell, per, x, y, half, grids)
		end
	else
		at = function(x, y)
			return blockersAt(world, tile, x, y, half)
		end
	end

	local toX = clamp(record.x + dir.x * step, half, w - half)
	record.x = moveAxis(record.x, toX, half, cell, function(x)
		return at(x, record.y)
	end)
	local toY = clamp(record.y + dir.y * step, half, h - half)
	record.y = moveAxis(record.y, toY, half, cell, function(y)
		return at(record.x, y)
	end)
end

return Mover
