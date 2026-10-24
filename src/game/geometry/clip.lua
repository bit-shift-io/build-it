-- A triangle list (src/game/geometry/primitives.lua's vertex format) cut at
-- a z plane, for a building's cutaway (docs/CONTEXT.md "Cutaway"). Pure;
-- plain LuaJIT.
local Clip = {}

-- The vertex where edge a-b crosses z = `z`: position and normal blended
-- (the normal kept unit length), a's colour, material, texture and slot.
local function crossing(a, b, z)
	local t = (z - a.z) / (b.z - a.z)
	local nx, ny, nz = a.nx + (b.nx - a.nx) * t, a.ny + (b.ny - a.ny) * t, a.nz + (b.nz - a.nz) * t
	local len = math.sqrt(nx * nx + ny * ny + nz * nz)
	if len == 0 then
		nx, ny, nz, len = a.nx, a.ny, a.nz, 1
	end
	return {
		x = a.x + (b.x - a.x) * t,
		y = a.y + (b.y - a.y) * t,
		z = z,
		nx = nx / len,
		ny = ny / len,
		nz = nz / len,
		r = a.r,
		g = a.g,
		b = a.b,
		material = a.material,
		texture = a.texture,
		slot = a.slot,
	}
end

-- `triangles` with everything above z = `z` cut away. A triangle wholly
-- above is dropped; one straddling the plane is cut and keeps its winding.
-- The cut is left open (no cap).
function Clip.below(triangles, z)
	local out = {}
	for i = 1, #triangles, 3 do
		local corners = { triangles[i], triangles[i + 1], triangles[i + 2] }
		local kept = {}
		for k = 1, 3 do
			local a, b = corners[k], corners[k % 3 + 1]
			if a.z <= z then
				kept[#kept + 1] = a
			end
			if (a.z <= z) ~= (b.z <= z) then
				kept[#kept + 1] = crossing(a, b, z)
			end
		end
		for k = 2, #kept - 1 do
			out[#out + 1] = kept[1]
			out[#out + 1] = kept[k]
			out[#out + 1] = kept[k + 1]
		end
	end
	return out
end

return Clip
