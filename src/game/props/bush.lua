-- Bush prop generator (docs/CONTEXT.md "Berry bush", "Prop generator"):
-- (rng, params) -> block model, 16 voxels per tile on a 1x1 footprint. Pure
-- and deterministic -- no `love.*`, every random choice comes from `rng`.
--
-- params.stage: 1 laden with berries, 2 a few left, 3 picked clean. Every
-- stage draws the same random choices, so a variant's later stages are the
-- same bush with fewer berries.
--
-- Shape numbers live here, not in config: they are the generator's design,
-- and a change to them must go with a VERSION bump to rebake the cache.
local Model = require("src.game.blocks.model")

local Bush = {}

-- Bump on any change to the output: it invalidates baked bush sprites.
Bush.VERSION = 1
Bush.STAGES = 3

local SIZE = 16 -- voxels per tile side
local BERRIES = 12 -- berry spots per bush
local KEPT = { BERRIES, 4, 0 } -- berries shown per stage

local LEAVES = {
	{ { 0.22, 0.5, 0.2 }, { 0.3, 0.6, 0.26 }, { 0.16, 0.4, 0.16 } },
	{ { 0.3, 0.52, 0.18 }, { 0.4, 0.62, 0.24 }, { 0.22, 0.42, 0.14 } },
	{ { 0.18, 0.46, 0.3 }, { 0.26, 0.56, 0.38 }, { 0.12, 0.36, 0.24 } },
}
local BERRY = {
	{ 0.78, 0.12, 0.2 },
	{ 0.5, 0.15, 0.6 },
	{ 0.2, 0.25, 0.75 },
}

function Bush.generate(rng, params)
	local stage = params.stage or 1
	local palette = LEAVES[rng:int(1, #LEAVES)]
	local berry = BERRY[rng:int(1, #BERRY)]

	local cx, cy = 8 + rng:range(-1, 1), 8 + rng:range(-1, 1)
	local rx = rng:range(4.5, 6.5)
	local ry, rz = rx * rng:range(0.8, 1.1), rng:range(3.5, 5.5)

	local grid, order = {}, {}
	for z = 0, math.ceil(rz) do
		for y = 0, SIZE - 1 do
			for x = 0, SIZE - 1 do
				local dx, dy, dz = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry, (z + 0.5) / rz
				if dx * dx + dy * dy + dz * dz <= 1 then
					local k = x .. "," .. y .. "," .. z
					grid[k] = { x = x, y = y, z = z }
					table.insert(order, k)
				end
			end
		end
	end
	for _, k in ipairs(order) do
		local c = grid[k]
		local r = rng:next()
		local above = grid[c.x .. "," .. c.y .. "," .. (c.z + 1)]
		c.color = (not above and r < 0.5) and palette[2] or (r < 0.3 and palette[3] or palette[1])
	end

	-- Berries sit on surface cells (nothing above), picked in draw order.
	local surface = {}
	for _, k in ipairs(order) do
		local c = grid[k]
		if not grid[c.x .. "," .. c.y .. "," .. (c.z + 1)] and c.z >= 1 then
			table.insert(surface, c)
		end
	end
	for i = 1, math.min(BERRIES, #surface) do
		local j = rng:int(i, #surface)
		surface[i], surface[j] = surface[j], surface[i]
		surface[i].berry = i
	end

	local model = Model.new(SIZE, 1, 1)
	for _, k in ipairs(order) do
		local c = grid[k]
		local color = c.color
		if c.berry and c.berry <= KEPT[stage] then
			color = berry
		end
		Model.addCell(model, { x = c.x, y = c.y, z = c.z, color = color })
	end
	return model
end

return Bush
