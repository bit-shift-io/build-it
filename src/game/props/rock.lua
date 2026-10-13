-- Rock prop generator (docs/CONTEXT.md "Prop generator"): (rng, params) ->
-- block model, 16 voxels per tile on a 1x1 footprint. Pure and
-- deterministic -- no `love.*`, every random choice comes from `rng`.
--
-- params.stage: 1 full rock, 2 broken down to its lower half, 3 a last
-- small chunk. Every stage draws the same random choices, so a variant's
-- later stages are cut from its full rock.
--
-- Shape numbers live here, not in config: they are the generator's design,
-- and a change to them must go with a VERSION bump to rebake the cache.
local Model = require("src.game.blocks.model")

local Rock = {}

-- Bump on any change to the output: it invalidates baked rock sprites.
Rock.VERSION = 1
Rock.STAGES = 3

local SIZE = 16 -- voxels per tile side
local LAST_CHUNK_RADIUS = 3.5 -- voxels, around the main lump's centre

-- Each palette: base, light, dark, and a fleck (moss, ore or lichen).
local STONE = {
	{ { 0.55, 0.55, 0.53 }, { 0.65, 0.65, 0.62 }, { 0.45, 0.45, 0.44 }, { 0.36, 0.5, 0.26 } },
	{ { 0.42, 0.46, 0.52 }, { 0.5, 0.54, 0.6 }, { 0.34, 0.37, 0.43 }, { 0.75, 0.62, 0.3 } },
	{ { 0.66, 0.56, 0.42 }, { 0.75, 0.65, 0.5 }, { 0.55, 0.46, 0.34 }, { 0.5, 0.36, 0.26 } },
	{ { 0.33, 0.32, 0.33 }, { 0.42, 0.41, 0.42 }, { 0.25, 0.24, 0.25 }, { 0.58, 0.62, 0.66 } },
}

local function stoneShade(rng, palette, top)
	local r = rng:next()
	if r < 0.06 then
		return palette[4]
	end
	if top and r < 0.5 then
		return palette[2]
	end
	if r < 0.3 then
		return palette[3]
	end
	return palette[1]
end

-- Fills a ground-hugging half-ellipsoid lump into `grid` (keyed "x,y,z").
local function lump(grid, order, cx, cy, rx, ry, rz)
	for z = 0, math.ceil(rz) do
		for y = 0, SIZE - 1 do
			for x = 0, SIZE - 1 do
				local dx, dy, dz = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry, (z + 0.5) / rz
				local k = x .. "," .. y .. "," .. z
				if dx * dx + dy * dy + dz * dz <= 1 and not grid[k] then
					grid[k] = { x = x, y = y, z = z }
					table.insert(order, k)
				end
			end
		end
	end
end

function Rock.generate(rng, params)
	local stage = params.stage or 1
	local palette = STONE[rng:int(1, #STONE)]

	local grid, order = {}, {}
	local cx, cy = 8 + rng:range(-1, 1), 8 + rng:range(-1, 1)
	local rx = rng:range(4.5, 7)
	lump(grid, order, cx, cy, rx, rx * rng:range(0.7, 1.1), rng:range(3, 7))
	for _ = 1, rng:int(1, 3) do
		local r = rng:range(2.5, 4.5)
		lump(grid, order, cx + rng:range(-3.5, 3.5), cy + rng:range(-3.5, 3.5), r, r * rng:range(0.8, 1.2), rng:range(2, 5))
	end

	local top = 0
	for _, k in ipairs(order) do
		top = math.max(top, grid[k].z)
	end
	-- Colour every cell, whatever the stage, so stages share one draw sequence.
	for _, k in ipairs(order) do
		local c = grid[k]
		local above = grid[c.x .. "," .. c.y .. "," .. (c.z + 1)]
		c.color = stoneShade(rng, palette, not above)
	end

	local model = Model.new(SIZE, 1, 1)
	local keepBelow = ({ math.huge, math.ceil(top * 0.55), math.max(1, math.ceil(top * 0.25)) })[stage]
	for _, k in ipairs(order) do
		local c = grid[k]
		local dx, dy = c.x + 0.5 - cx, c.y + 0.5 - cy
		local inChunk = stage < 3 or dx * dx + dy * dy <= LAST_CHUNK_RADIUS * LAST_CHUNK_RADIUS
		if c.z < keepBelow and inChunk then
			Model.addCell(model, { x = c.x, y = c.y, z = c.z, color = c.color })
		end
	end
	return model
end

return Rock
