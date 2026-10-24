-- The character prop (docs/CONTEXT.md "Prop generator", "Facing"): a figure
-- of posed voxel parts -- legs, body, arms, head and its features -- one
-- block model per (direction, frame), 16 voxels per tile on a 1x1
-- footprint. Pure and deterministic -- no `love.*`.
--
-- Parts are boxes in the figure's own frame: u to its right hand, v forward,
-- z up, in voxels from the footprint centre. A pose offsets parts in that
-- frame. Nothing ever turns by 45 degrees, which would alias on the voxel
-- grid: the body is laid out along a cardinal `base` (diagonals take N or
-- S), forward pose offsets step along the true direction (a diagonal stride
-- moves one cell on each axis), and on diagonals the head's features turn
-- by one voxel -- the face slides toward the turn, the back hair away from
-- it. The camera sees only south faces and tops, so every view reads from
-- where the parts sit, never from an east or west face.
--
-- Shape numbers live here, not in config, tied to VERSION like every prop
-- generator: change the figure, bump VERSION, and the cache rebakes.
local Model = require("src.game.blocks.model")

local Character = {}

-- Bump on any change to the output: it invalidates baked character frames.
Character.VERSION = 2

-- The 8 facings, clockwise from north: the unit-grid step (x east, y south)
-- it walks along, the cardinal its body is laid out on, and its turn from
-- that cardinal (+1 clockwise seen from above, -1 anticlockwise).
Character.DIRECTIONS = {
	{ name = "N", x = 0, y = -1, base = "N", turn = 0 },
	{ name = "NE", x = 1, y = -1, base = "N", turn = 1 },
	{ name = "E", x = 1, y = 0, base = "E", turn = 0 },
	{ name = "SE", x = 1, y = 1, base = "S", turn = -1 },
	{ name = "S", x = 0, y = 1, base = "S", turn = 0 },
	{ name = "SW", x = -1, y = 1, base = "S", turn = 1 },
	{ name = "W", x = -1, y = 0, base = "W", turn = 0 },
	{ name = "NW", x = -1, y = -1, base = "N", turn = -1 },
}

-- Forward and right-hand grid steps of each cardinal base.
local BASES = {
	N = { fx = 0, fy = -1, rx = 1, ry = 0 },
	E = { fx = 1, fy = 0, rx = 0, ry = 1 },
	S = { fx = 0, fy = 1, rx = -1, ry = 0 },
	W = { fx = -1, fy = 0, rx = 0, ry = -1 },
}

-- Frames: 1 stands idle, 2..5 are the walk cycle in order.
Character.IDLE = 1
Character.WALK = { 2, 3, 4, 5 }
Character.FRAMES = 5

local SIZE = 32 -- voxels per tile side
local CENTRE = SIZE / 2

local SKIN = { 0.94, 0.76, 0.6 }
local HAIR = { 0.35, 0.22, 0.12 }
local SHIRT = { 0.2, 0.45, 0.75 }
local TROUSERS = { 0.25, 0.27, 0.38 }
local SHOES = { 0.16, 0.12, 0.1 }
local EYES = { 0.08, 0.08, 0.1 }

-- In draw order: a later part's cells replace an earlier one's. box =
-- { u0, u1, v0, v1, z0, z1 } (max exclusive); `bottom` colours the lowest
-- layer (shoes, hands). Features move with their `bone` and, on diagonals,
-- turn with the head; `paint` features only recolour cells already there.
local PARTS = {
	{ name = "legL", box = { -2, 0, -1, 1, 0, 5 }, color = TROUSERS, bottom = SHOES },
	{ name = "legR", box = { 0, 2, -1, 1, 0, 5 }, color = TROUSERS, bottom = SHOES },
	{ name = "body", box = { -3, 3, -2, 2, 5, 10 }, color = SHIRT },
	{ name = "armL", box = { -5, -3, -1, 1, 5, 10 }, color = SHIRT, bottom = SKIN },
	{ name = "armR", box = { 3, 5, -1, 1, 5, 10 }, color = SHIRT, bottom = SKIN },
	-- Shallow front to back: the camera sees a top as deep as the part, so
	-- a deep head would read as a tall hat.
	{ name = "head", box = { -3, 3, -2, 2, 10, 15 }, color = SKIN },
	-- Hair over the top and the back half: a figure facing away shows it.
	{ name = "hair", bone = "head", feature = true, paint = true, box = { -3, 3, -2, 0, 11, 15 }, color = HAIR },
	{ name = "hair", bone = "head", paint = true, box = { -3, 3, -2, 2, 14, 15 }, color = HAIR },
	{ name = "eyes", bone = "head", feature = true, paint = true, box = { -2, -1, 1, 2, 12, 13 }, color = EYES },
	{ name = "eyes", bone = "head", feature = true, paint = true, box = { 1, 2, 1, 2, 12, 13 }, color = EYES },
	-- Sticks out past the face, so a side view shows which way it looks.
	{ name = "nose", bone = "head", feature = true, box = { -1, 1, 2, 3, 11, 12 }, color = SKIN },
}

-- Per frame, offsets { u, v, z } by bone (a part's bone is its own name
-- unless it says otherwise). The walk: a stride with the left leg forward
-- and the back foot's heel up, the right leg passing lifted, the mirrored
-- stride, the left leg passing. Arms swing against the legs.
local STRIDE = 2 -- voxels a foot or hand swings forward or back
local POSES = {
	[1] = {},
	[2] = {
		legL = { 0, STRIDE, 0 },
		legR = { 0, -STRIDE, 1 },
		armL = { 0, -STRIDE, 0 },
		armR = { 0, STRIDE, 0 },
	},
	[3] = { legR = { 0, 0, 1 } },
	[4] = {
		legL = { 0, -STRIDE, 1 },
		legR = { 0, STRIDE, 0 },
		armL = { 0, STRIDE, 0 },
		armR = { 0, -STRIDE, 0 },
	},
	[5] = { legL = { 0, 0, 1 } },
}

local ZERO = { 0, 0, 0 }

-- Puts the part's box into `grid`: offset along the base's right hand (u)
-- and up (z), then stepped `v` times along the true direction.
-- `shirt` replaces SHIRT, the body's and arms' colour.
local function rasterise(grid, order, p, d, offset, shirt)
	local base = BASES[d.base]
	local u0, u1, v0, v1, z0, z1 = unpack(p.box)
	local du = offset[1]
	-- A diagonal head turns: what faces forward slides toward the turn,
	-- what faces back away from it.
	if p.feature and d.turn ~= 0 then
		local mid = (v0 + v1) / 2
		du = du + (mid > 0 and d.turn or mid < 0 and -d.turn or 0)
	end
	-- A diagonal step covers about as much ground as a straight one.
	local len = math.sqrt(d.x * d.x + d.y * d.y)
	local shiftX = math.floor(offset[2] * d.x / len + 0.5)
	local shiftY = math.floor(offset[2] * d.y / len + 0.5)
	for z = z0 + offset[3], z1 + offset[3] - 1 do
		for y = 0, SIZE - 1 do
			for x = 0, SIZE - 1 do
				local dx, dy = x - shiftX + 0.5 - CENTRE, y - shiftY + 0.5 - CENTRE
				local u = dx * base.rx + dy * base.ry - du
				local v = dx * base.fx + dy * base.fy
				local k = x .. "," .. y .. "," .. z
				if u > u0 and u < u1 and v > v0 and v < v1 and (grid[k] or not p.paint) then
					if not grid[k] then
						order[#order + 1] = k
					end
					local color = (z == z0 + offset[3] and p.bottom) or (p.color == SHIRT and shirt) or p.color
					grid[k] = { x = x, y = y, z = z, color = color, part = p.name }
				end
			end
		end
	end
end

-- The block model of the figure facing Character.DIRECTIONS[direction] in
-- frame `frame` (Character.IDLE or one of Character.WALK). Each cell carries
-- `part`, the name of the part it belongs to. `shirt` ({ r, g, b },
-- optional) recolours the shirt: villagers wear their own.
function Character.model(direction, frame, shirt)
	local d = assert(Character.DIRECTIONS[direction], "unknown direction " .. tostring(direction))
	local pose = assert(POSES[frame], "unknown frame " .. tostring(frame))
	local grid, order = {}, {}
	for _, p in ipairs(PARTS) do
		rasterise(grid, order, p, d, pose[p.bone or p.name] or ZERO, shirt or SHIRT)
	end
	local model = Model.new(SIZE, 1, 1)
	for _, k in ipairs(order) do
		Model.addCell(model, grid[k])
	end
	return model
end

-- The prop generator form (src/game/props/registry.lua): params.variant is
-- the direction and params.stage the frame. The figure draws nothing
-- random, so `rng` goes unused.
function Character.generate(_rng, params)
	return Character.model(params.variant, params.stage)
end

return Character
