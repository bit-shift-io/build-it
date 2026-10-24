-- The character prop (docs/CONTEXT.md "Prop generator", "Facing"): a figure
-- of posed voxel parts -- legs, body, arms, head and its features -- one
-- block model per frame, 32 voxels per tile on a 1x1 footprint, always
-- facing N. Pure and deterministic -- no `love.*`.
--
-- Parts are boxes in the figure's own frame: u to its right hand (east), v
-- forward (north), z up, in voxels from the footprint centre. A pose offsets
-- parts in that frame. Facing never shapes the voxels: the baker turns the
-- figure's mesh to each of the 8 facings (Registry.turn, Mesh.yaw), which
-- avoids the staircase a 45-degree voxel layout would alias into.
--
-- Shape numbers live here, not in config, tied to VERSION like every prop
-- generator: change the figure, bump VERSION, and the cache rebakes.
local Model = require("src.game.blocks.model")

local Character = {}

-- Bump on any change to the output: it invalidates baked character frames.
Character.VERSION = 3

-- The 8 facings, clockwise from north: the unit-grid step (x east, y south)
-- it walks along. Facing k bakes the figure turned (k - 1) x 45 degrees.
Character.DIRECTIONS = {
	{ name = "N", x = 0, y = -1 },
	{ name = "NE", x = 1, y = -1 },
	{ name = "E", x = 1, y = 0 },
	{ name = "SE", x = 1, y = 1 },
	{ name = "S", x = 0, y = 1 },
	{ name = "SW", x = -1, y = 1 },
	{ name = "W", x = -1, y = 0 },
	{ name = "NW", x = -1, y = -1 },
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
-- layer (shoes, hands). Parts move with their `bone`; `paint` parts only
-- recolour cells already there.
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
	{ name = "hair", bone = "head", paint = true, box = { -3, 3, -2, 0, 11, 15 }, color = HAIR },
	{ name = "hair", bone = "head", paint = true, box = { -3, 3, -2, 2, 14, 15 }, color = HAIR },
	{ name = "eyes", bone = "head", paint = true, box = { -2, -1, 1, 2, 12, 13 }, color = EYES },
	{ name = "eyes", bone = "head", paint = true, box = { 1, 2, 1, 2, 12, 13 }, color = EYES },
	-- Sticks out past the face, so a side view shows which way it looks.
	{ name = "nose", bone = "head", box = { -1, 1, 2, 3, 11, 12 }, color = SKIN },
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

-- Puts the part's box, moved by `offset`, into `grid`: u runs east (+x), v
-- north (-y). `shirt` replaces SHIRT, the body's and arms' colour.
local function rasterise(grid, order, p, offset, shirt)
	local u0, u1, v0, v1, z0, z1 = unpack(p.box)
	u0, u1, v0, v1 = u0 + offset[1], u1 + offset[1], v0 + offset[2], v1 + offset[2]
	for z = z0 + offset[3], z1 + offset[3] - 1 do
		for v = v0, v1 - 1 do
			for u = u0, u1 - 1 do
				local x, y = CENTRE + u, CENTRE - 1 - v
				local k = x .. "," .. y .. "," .. z
				if grid[k] or not p.paint then
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

-- The block model of the figure, facing N, in frame `frame`
-- (Character.IDLE or one of Character.WALK). Each cell carries `part`, the
-- name of the part it belongs to. `shirt` ({ r, g, b }, optional) recolours
-- the shirt: villagers wear their own.
function Character.model(frame, shirt)
	local pose = assert(POSES[frame], "unknown frame " .. tostring(frame))
	local grid, order = {}, {}
	for _, p in ipairs(PARTS) do
		rasterise(grid, order, p, pose[p.bone or p.name] or ZERO, shirt or SHIRT)
	end
	local model = Model.new(SIZE, 1, 1)
	for _, k in ipairs(order) do
		Model.addCell(model, grid[k])
	end
	return model
end

-- The prop generator form (src/game/props/registry.lua): params.stage is
-- the frame. params.variant, the facing, is the baker's turn
-- (Registry.turn), not the model's. The figure draws nothing random, so
-- `rng` goes unused.
function Character.generate(_rng, params)
	return Character.model(params.stage)
end

return Character
