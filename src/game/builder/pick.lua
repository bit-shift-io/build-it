-- Ray picking for the builder: which brick a screen ray hits, and where a
-- new brick would snap to. Pure -- no `love.*`; the app hands in the ray
-- from its camera (src/app/builder_camera.lua).
--
-- Rays are in draft space (src/game/builder/draft.lua): studs, x east,
-- y south, z up in brick layers. origin and dir are { x, y, z }; dir need
-- not be unit length.
local Bricks = require("src.game.builder.bricks")

local Pick = {}

-- How far the baseplate's slab reaches below its top, in layers. Only its
-- top takes bricks; the slab just stops rays that pass beside the bricks.
local BASEPLATE_THICKNESS = 0.5

-- Slab order, with each axis's index into origin/dir. z comes first so a
-- ray meeting a top face and a side face at once -- on the seam between
-- two brick tops -- counts as a top hit and stacks.
local AXES = { { "z", 3 }, { "x", 1 }, { "y", 2 } }

local function brickBox(b)
	return { x = b.x, y = b.y, z = b.z, maxX = b.x + b.width, maxY = b.y + b.depth, maxZ = b.z + 1, brick = b }
end

local function baseplateBox(draft, cfg)
	local studs = cfg.studsPerTile
	return { x = 0, y = 0, z = -BASEPLATE_THICKNESS, maxX = draft.width * studs, maxY = draft.depth * studs, maxZ = 0 }
end

-- Slab test: the entry distance along the ray and the entry face's axis and
-- sign, or nil when the ray misses the box or starts inside it.
local function enter(box, origin, dir)
	local near, far, axis, sign = -math.huge, math.huge, nil, 0
	for _, axisIndex in ipairs(AXES) do
		local a, i = axisIndex[1], axisIndex[2]
		local lo, hi = box[a], box["max" .. a:upper()]
		if dir[i] == 0 then
			if origin[i] < lo or origin[i] > hi then
				return nil
			end
		else
			local t1, t2 = (lo - origin[i]) / dir[i], (hi - origin[i]) / dir[i]
			local s = dir[i] > 0 and -1 or 1 -- the face the ray enters through
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			if t1 > near then
				near, axis, sign = t1, a, s
			end
			far = math.min(far, t2)
		end
	end
	if near > far or near <= 0 or not axis then
		return nil
	end
	return near, axis, sign
end

local function clamp(v, lo, hi)
	return math.max(lo, math.min(hi, v))
end

-- The cell a new bw x bd brick takes against `box`'s entry face, so that
-- the brick covers the studs nearest the hit point.
local function placement(draft, box, axis, sign, point, cfg, bw, bd)
	local place = {
		x = math.floor(point[1] - bw / 2 + 0.5),
		y = math.floor(point[2] - bd / 2 + 0.5),
		z = math.max(0, box.z),
	}
	if axis == "z" then
		-- On top: keep the brick on the baseplate, even when the cursor is
		-- on an edge stud.
		local studs = cfg.studsPerTile
		place.x = clamp(place.x, 0, draft.width * studs - bw)
		place.y = clamp(place.y, 0, draft.depth * studs - bd)
		place.z = sign > 0 and box.maxZ or box.z - 1
	elseif axis == "x" then
		place.x = sign > 0 and box.maxX or box.x - bw
	else
		place.y = sign > 0 and box.maxY or box.y - bd
	end
	return place
end

-- Casts a ray at the draft. Returns the nearest hit, or nil:
--   { brick = <the brick hit, nil for the baseplate>,
--     place = { x, y, z } } -- where Draft.place would put the held brick
-- `place` is a suggestion; Draft.place still refuses it if it doesn't fit.
-- held is the brick in hand (src/game/builder/draft.lua), cfg.held if nil.
-- Every brick, slopes included, picks as its bounding box: a ray through
-- the empty wedge above a slope still hits the slope.
function Pick.cast(draft, origin, dir, cfg, held)
	held = held or cfg.held
	local best, bestT = nil, math.huge
	local boxes = { baseplateBox(draft, cfg) }
	for _, b in ipairs(draft.bricks) do
		table.insert(boxes, brickBox(b))
	end
	for _, box in ipairs(boxes) do
		local t, axis, sign = enter(box, origin, dir)
		if t and t < bestT then
			best, bestT = { box = box, axis = axis, sign = sign }, t
		end
	end
	if not best then
		return nil
	end
	local point = { origin[1] + dir[1] * bestT, origin[2] + dir[2] * bestT, origin[3] + dir[3] * bestT }
	return {
		brick = best.box.brick,
		place = placement(draft, best.box, best.axis, best.sign, point, cfg, Bricks.footprint(held.shape, held.rotation, cfg)),
	}
end

return Pick
