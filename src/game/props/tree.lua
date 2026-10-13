-- Tree prop generator (docs/CONTEXT.md "Prop generator"): (rng, params) ->
-- block model, 16 voxels per tile on a 1x1 footprint. Pure and
-- deterministic -- no `love.*`, every random choice comes from `rng`.
--
-- params.stage: 1 full tree, 2 half-felled (trunk cut halfway, crown gone),
-- 3 stump. Every stage draws the same random choices, so a variant's stump
-- matches its tree.
--
-- Shape numbers live here, not in config: they are the generator's design,
-- and a change to them must go with a VERSION bump to rebake the cache.
local Model = require("src.game.blocks.model")

local Tree = {}

-- Bump on any change to the output: it invalidates baked tree sprites.
Tree.VERSION = 1
Tree.STAGES = 3

local SIZE = 16 -- voxels per tile side
local STUMP_HEIGHT = 2

local BARK = { { 0.42, 0.28, 0.16 }, { 0.36, 0.24, 0.14 }, { 0.5, 0.36, 0.22 } }
local CUT_WOOD = { 0.8, 0.66, 0.44 }
-- Shades per palette: base, light, dark.
local LEAVES = {
	{ { 0.24, 0.52, 0.2 }, { 0.32, 0.62, 0.25 }, { 0.18, 0.42, 0.16 } },
	{ { 0.15, 0.4, 0.24 }, { 0.2, 0.48, 0.29 }, { 0.11, 0.32, 0.19 } },
	{ { 0.44, 0.58, 0.2 }, { 0.53, 0.66, 0.26 }, { 0.36, 0.49, 0.16 } },
	{ { 0.6, 0.42, 0.16 }, { 0.7, 0.5, 0.2 }, { 0.5, 0.33, 0.12 } },
}

-- A cell grid where later puts replace earlier ones, kept in first-put order
-- so the output is the same every run.
local function newGrid()
	local grid = { cells = {}, order = {} }
	function grid.put(x, y, z, color, part)
		if x < 0 or y < 0 or x >= SIZE or y >= SIZE or z < 0 then
			return
		end
		local k = x .. "," .. y .. "," .. z
		if not grid.cells[k] then
			table.insert(grid.order, k)
		end
		grid.cells[k] = { x = x, y = y, z = z, color = color, part = part }
	end
	return grid
end

local function pick(rng, list)
	return list[rng:int(1, #list)]
end

-- A leaf shade: mostly base, lighter near the top of the crown, some dark.
local function leafShade(rng, palette, high)
	local r = rng:next()
	if high and r < 0.5 then
		return palette[2]
	end
	if r < 0.2 then
		return palette[3]
	end
	return palette[1]
end

local function ellipsoid(grid, rng, palette, cx, cy, cz, rx, rz)
	for z = math.floor(cz - rz), math.ceil(cz + rz) do
		for y = 0, SIZE - 1 do
			for x = 0, SIZE - 1 do
				local dx, dy, dz = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / rx, (z + 0.5 - cz) / rz
				if dx * dx + dy * dy + dz * dz <= 1 then
					grid.put(x, y, z, leafShade(rng, palette, z + 0.5 > cz + rz * 0.3), "crown")
				end
			end
		end
	end
end

-- A broadleaf: a few overlapping round blobs on a trunk.
local function roundCrown(grid, rng, palette, trunkTop)
	local cx, cy = 8 + rng:range(-1, 1), 8 + rng:range(-1, 1)
	local cz = trunkTop + rng:range(1, 3)
	ellipsoid(grid, rng, palette, cx, cy, cz, rng:range(5, 7.5), rng:range(3.5, 5.5))
	for _ = 1, rng:int(1, 3) do
		local bx, by = cx + rng:range(-3, 3), cy + rng:range(-3, 3)
		ellipsoid(grid, rng, palette, bx, by, cz + rng:range(-2, 3), rng:range(3, 5), rng:range(2.5, 4))
	end
end

-- A conifer: stacked discs narrowing to a point, banded into tiers.
local function coneCrown(grid, rng, palette, base, top)
	local maxRadius = rng:range(5, 7.5)
	local band = rng:int(3, 4)
	for z = base, top do
		local f = (z - base) / (top - base + 1)
		local r = maxRadius * (1 - f) * (1 - 0.3 * ((z - base) % band) / band) + 0.5
		for y = 0, SIZE - 1 do
			for x = 0, SIZE - 1 do
				local dx, dy = x + 0.5 - 8, y + 0.5 - 8
				if dx * dx + dy * dy <= r * r then
					grid.put(x, y, z, leafShade(rng, palette, z > top - 3), "crown")
				end
			end
		end
	end
end

function Tree.generate(rng, params)
	local stage = params.stage or 1
	local grid = newGrid()

	local thickness = rng:int(2, 3)
	local tx0 = rng:int(6, 9 - thickness)
	local ty0 = rng:int(6, 9 - thickness)
	local bark = pick(rng, BARK)
	local palette = pick(rng, LEAVES)
	local conifer = rng:next() < 0.4

	local trunkTop
	if conifer then
		local top = rng:int(20, 27)
		trunkTop = top - 4 -- hidden inside the crown, short of its narrow tip
		coneCrown(grid, rng, palette, rng:int(3, 5), top)
	else
		trunkTop = rng:int(9, 14)
		roundCrown(grid, rng, palette, trunkTop)
	end

	-- Stages cut the trunk and drop the crown.
	local trunkHeight = ({ trunkTop, math.floor(trunkTop / 2), STUMP_HEIGHT })[stage]
	for z = 0, trunkHeight - 1 do
		for y = ty0, ty0 + thickness - 1 do
			for x = tx0, tx0 + thickness - 1 do
				grid.put(x, y, z, (stage > 1 and z == trunkHeight - 1) and CUT_WOOD or bark, "trunk")
			end
		end
	end

	local model = Model.new(SIZE, 1, 1)
	for _, k in ipairs(grid.order) do
		local c = grid.cells[k]
		if stage == 1 or c.part == "trunk" then
			Model.addCell(model, { x = c.x, y = c.y, z = c.z, color = c.color })
		end
	end
	return model
end

return Tree
