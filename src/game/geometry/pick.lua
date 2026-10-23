-- Picking (docs/CONTEXT.md "Builder"): which node a ray from the builder's
-- camera hits. Pure; plain LuaJIT. Lengths in tiles.
--
-- A resolved tree's geometry (src/game/geometry/mesh.lua) split by the
-- node the builder selects for it: each primitive's own id, and for
-- everything inside a prefab instance the instance's id (its children are
-- the prefab's, not the design's).
local Mesh = require("src.game.geometry.mesh")

local Pick = {}

-- `node`'s targets in its parent's space, appended to `out`.
local function collect(node, out)
	local own = {}
	if node.kind == "prefab" or node.kind == "extrude" or node.kind == "lathe" or node.kind == "sweep" or not node.children then
		local triangles = Mesh.merge(Mesh.parts(node))
		if #triangles > 0 then
			out[#out + 1] = { id = node.id, triangles = triangles }
		end
		return out
	end
	for _, child in ipairs(node.children) do
		collect(child, own)
	end
	for _, target in ipairs(own) do
		out[#out + 1] = { id = target.id, triangles = Mesh.transform(target.triangles, node.transform) }
	end
	return out
end

-- The geometry of the resolved tree under `root` by owning node:
-- { { id, triangles }, ... }, every transform applied.
function Pick.targets(root)
	return collect(root, {})
end

-- Möller–Trumbore: how far along the ray (o, d) triangle (a, b, c) lies,
-- or nil when the ray misses it or it lies behind.
local EPSILON = 1e-9
local function hit(o, d, a, b, c)
	local e1x, e1y, e1z = b.x - a.x, b.y - a.y, b.z - a.z
	local e2x, e2y, e2z = c.x - a.x, c.y - a.y, c.z - a.z
	local px, py, pz = d[2] * e2z - d[3] * e2y, d[3] * e2x - d[1] * e2z, d[1] * e2y - d[2] * e2x
	local det = e1x * px + e1y * py + e1z * pz
	if math.abs(det) < EPSILON then
		return nil
	end
	local inv = 1 / det
	local tx, ty, tz = o[1] - a.x, o[2] - a.y, o[3] - a.z
	local u = (tx * px + ty * py + tz * pz) * inv
	if u < 0 or u > 1 then
		return nil
	end
	local qx, qy, qz = ty * e1z - tz * e1y, tz * e1x - tx * e1z, tx * e1y - ty * e1x
	local v = (d[1] * qx + d[2] * qy + d[3] * qz) * inv
	if v < 0 or u + v > 1 then
		return nil
	end
	local t = (e2x * qx + e2y * qy + e2z * qz) * inv
	if t <= EPSILON then
		return nil
	end
	-- The face's unit normal, turned towards the ray.
	local nx, ny, nz = e1y * e2z - e1z * e2y, e1z * e2x - e1x * e2z, e1x * e2y - e1y * e2x
	local len = math.sqrt(nx * nx + ny * ny + nz * nz)
	if nx * d[1] + ny * d[2] + nz * d[3] > 0 then
		len = -len
	end
	return t, { nx / len + 0, ny / len + 0, nz / len + 0 }
end

-- The id of the target (Pick.targets) the ray from `origin` along
-- `direction` ({ x, y, z } each) meets first, and how far along it in
-- lengths of `direction`, and the unit normal { x, y, z } of the face it
-- meets, turned towards the ray; nil when it meets none.
function Pick.at(targets, origin, direction)
	local best, nearest, face = nil, math.huge, nil
	for _, target in ipairs(targets) do
		local tris = target.triangles
		for i = 1, #tris, 3 do
			local t, normal = hit(origin, direction, tris[i], tris[i + 1], tris[i + 2])
			if t and t < nearest then
				best, nearest, face = target.id, t, normal
			end
		end
	end
	return best, best and nearest, face
end

return Pick
