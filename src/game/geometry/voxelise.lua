-- Voxel counts of a design's geometry (docs/CONTEXT.md "Voxel", ADR 0006:
-- cost and traits come from voxelising, never from analytic volume). Pure;
-- plain LuaJIT.
--
-- A voxel counts when its centre lies inside a part. Each part is one
-- closed primitive (Mesh.parts), clipped at the ground: a vertical ray up
-- from the centre crosses its surface an odd number of times when inside.
-- The ground cut is open, but no upward ray from above ground meets it.
-- Parts are tested one by one, so overlapping parts count each voxel once.
local Voxelise = {}

-- Rays run this far off the voxel centre so they never graze a triangle
-- edge or vertex exactly; far below a voxel.
local NUDGE_X, NUDGE_Y = 1.37e-7, 2.91e-7

-- The heights where the vertical line through (x, y) crosses triangle
-- (a, b, c), appended to `hits`; a triangle seen edge-on from above has
-- none.
local function crossing(a, b, c, x, y, hits)
	local d = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
	if d == 0 then
		return
	end
	local u = ((b.y - c.y) * (x - c.x) + (c.x - b.x) * (y - c.y)) / d
	local v = ((c.y - a.y) * (x - c.x) + (a.x - c.x) * (y - c.y)) / d
	local w = 1 - u - v
	if u < 0 or v < 0 or w < 0 then
		return
	end
	hits[#hits + 1] = u * a.z + v * b.z + w * c.z
end

-- Every column (i, j) of voxel centres a triangle's shadow covers, with the
-- heights its surface crosses them at: columns[i][j] = { z, ... }.
local function columns(triangles, perTile)
	local out = {}
	for t = 1, #triangles, 3 do
		local a, b, c = triangles[t], triangles[t + 1], triangles[t + 2]
		local i0 = math.ceil(math.min(a.x, b.x, c.x) * perTile - 0.5)
		local i1 = math.floor(math.max(a.x, b.x, c.x) * perTile - 0.5)
		local j0 = math.ceil(math.min(a.y, b.y, c.y) * perTile - 0.5)
		local j1 = math.floor(math.max(a.y, b.y, c.y) * perTile - 0.5)
		for i = i0, i1 do
			local x = (i + 0.5) / perTile + NUDGE_X
			for j = j0, j1 do
				local y = (j + 0.5) / perTile + NUDGE_Y
				out[i] = out[i] or {}
				local hits = out[i][j] or {}
				local before = #hits
				crossing(a, b, c, x, y, hits)
				if #hits > before then
					out[i][j] = hits
				end
			end
		end
	end
	return out
end

-- Voxel keys pack (i, j, k) into one exact number; each index stays well
-- inside +-SPAN / 2.
local SPAN = 65536

-- Marks the voxels inside `triangles` (one closed part) in `filled`;
-- voxels already filled keep their material.
-- Counts new voxels into counts[material].
local function fill(triangles, material, perTile, filled, counts)
	for i, column in pairs(columns(triangles, perTile)) do
		for j, hits in pairs(column) do
			table.sort(hits)
			-- Inside between each pair of crossings, top down; an odd one
			-- out at the bottom is inside down to the ground cut.
			for h = #hits, 1, -2 do
				local k0 = math.max(0, math.ceil((hits[h - 1] or 0) * perTile - 0.5))
				local k1 = math.floor(hits[h] * perTile - 0.5)
				for k = k0, k1 do
					-- Numeric, so -0 and 0 are one key.
					local key = (i * SPAN + j) * SPAN + k
					if not filled[key] then
						filled[key] = true
						counts[material] = (counts[material] or 0) + 1
					end
				end
			end
		end
	end
end

-- The voxels, `perTile` to a tile side, inside `parts` ({ { triangles,
-- material }, ... }), each counted once: { [material] = count }. Where
-- parts overlap, the earlier part's material wins.
function Voxelise.of(parts, perTile)
	local filled, counts = {}, {}
	for _, part in ipairs(parts) do
		fill(part.triangles, part.material, perTile, filled, counts)
	end
	return counts
end

return Voxelise
