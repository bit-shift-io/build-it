-- Deer prop generator (docs/CONTEXT.md "Deer", "Prop generator"):
-- (rng, params) -> block model, 16 voxels per tile on a 1x1 footprint. Pure
-- and deterministic -- no `love.*`.
--
-- params.variant: the facing, an index into Character.DIRECTIONS (the
-- animator's facing). The body lies along the facing's cardinal base (a
-- diagonal takes N or S), head forward. params.stage: the animator frame --
-- 1 stands, 2..5 are the walk cycle, legs in diagonal pairs.
--
-- Shape numbers live here, not in config; a change goes with a VERSION bump.
local Model = require("src.game.blocks.model")
local Character = require("src.game.props.character")

local Deer = {}

-- Bump on any change to the output: it invalidates baked deer sprites.
Deer.VERSION = 1

local SIZE = 16 -- voxels per tile side
local CENTRE = SIZE / 2

local COAT = { 0.55, 0.36, 0.2 }
local BELLY = { 0.72, 0.56, 0.38 }
local DARK = { 0.3, 0.2, 0.12 }
local TAIL = { 0.92, 0.88, 0.8 }

-- Forward and right-hand grid steps of each cardinal base.
local BASES = {
	N = { fx = 0, fy = -1, rx = 1, ry = 0 },
	E = { fx = 1, fy = 0, rx = 0, ry = 1 },
	S = { fx = 0, fy = 1, rx = -1, ry = 0 },
	W = { fx = -1, fy = 0, rx = 0, ry = -1 },
}

-- A leg's forward offset in voxels per walk stage (stage 1 stands).
local STRIDE_OF = { [1] = 0, [2] = 1, [3] = 0, [4] = -1, [5] = 0 }

-- In draw order, boxes { u0, u1, v0, v1, z0, z1 } (max exclusive) in the
-- deer's own frame: u to its right, v forward, z up. `pair` legs swing with
-- the stride, the other pair against it.
local PARTS = {
	{ box = { -2, -1, -3, -2, 0, 5 }, color = DARK, leg = 1 },
	{ box = { 1, 2, 1, 2, 0, 5 }, color = DARK, leg = 1 },
	{ box = { 1, 2, -3, -2, 0, 5 }, color = DARK, leg = -1 },
	{ box = { -2, -1, 1, 2, 0, 5 }, color = DARK, leg = -1 },
	{ box = { -2, 2, -4, 3, 5, 9 }, color = COAT },
	{ box = { -1, 1, -4, 3, 5, 6 }, color = BELLY },
	{ box = { -1, 1, 2, 4, 8, 12 }, color = COAT },
	{ box = { -1, 1, 3, 6, 11, 14 }, color = COAT },
	{ box = { -1, 1, 5, 6, 11, 12 }, color = DARK },
	{ box = { 0, 1, -5, -4, 8, 10 }, color = TAIL },
}

function Deer.generate(_rng, params)
	local dir = Character.DIRECTIONS[params.variant or 5]
	local b = BASES[dir.base]
	local swing = STRIDE_OF[params.stage or 1] or 0
	local model = Model.new(SIZE, 1, 1)
	local seen = {}
	for _, part in ipairs(PARTS) do
		local box = part.box
		local dv = part.leg and part.leg * swing or 0
		for u = box[1], box[2] - 1 do
			for v = box[3] + dv, box[4] - 1 + dv do
				local wx = math.floor(CENTRE + b.fx * (v + 0.5) + b.rx * (u + 0.5))
				local wy = math.floor(CENTRE + b.fy * (v + 0.5) + b.ry * (u + 0.5))
				for z = box[5], box[6] - 1 do
					local k = wx .. "," .. wy .. "," .. z
					if seen[k] then
						seen[k].color = part.color
					else
						seen[k] = Model.addCell(model, { x = wx, y = wy, z = z, color = part.color })
					end
				end
			end
		end
	end
	return model
end

return Deer
