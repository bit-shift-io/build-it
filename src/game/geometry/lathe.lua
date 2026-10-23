-- Lathe (docs/CONTEXT.md "Operation"): a shape revolved about its work
-- plane's v axis through the plane origin. The plane's u coordinate is the
-- distance from the axis, so the profile must keep u >= 0; v is the height
-- along the axis. A positive angle turns toward the plane's normal (u x v).
-- A full 360 degrees is closed; a partial turn gets a cap at each end. Pure;
-- plain LuaJIT.
local Shape2d = require("src.game.geometry.shape2d")
local Triangulate = require("src.game.geometry.triangulate")

local Lathe = {}

local EPSILON = 1e-9

local function unit(x, y, z)
	local len = math.sqrt(x * x + y * y + z * z)
	return x / len, y / len, z / len
end

-- Whether every point of `outline` lies on the axis or on the plane's u
-- side of it.
function Lathe.valid(outline)
	for _, p in ipairs(outline) do
		if p[1] < -EPSILON then
			return false
		end
	end
	return true
end

-- The solid of `shape` ({ points, plane = { origin, u, v } }) revolved
-- `angle` degrees (-360 to 360, not 0) in `segments` steps, in the shape's
-- own space. Triangles as in src/game/geometry/primitives.lua, in `color`,
-- wound outward with flat normals; empty when the outline is unusable or
-- crosses the axis.
function Lathe.mesh(shape, angle, segments, color)
	local outline = Shape2d.outline(shape.points)
	if not outline or not Lathe.valid(outline) then
		return {}
	end
	local o, u, v = shape.plane.origin, shape.plane.u, shape.plane.v
	local nx, ny, nz = unit(u[2] * v[3] - u[3] * v[2], u[3] * v[1] - u[1] * v[3], u[1] * v[2] - u[2] * v[1])
	local ulen = math.sqrt(u[1] * u[1] + u[2] * u[2] + u[3] * u[3])
	local full = math.abs(angle) >= 360
	local rings = full and segments or segments + 1
	local count = #outline

	-- point[ring][i]: outline point i turned to ring's angle.
	local point = {}
	for s = 1, rings do
		local theta = math.rad(angle) * (s - 1) / segments
		local c, sn = math.cos(theta), math.sin(theta)
		local ring = {}
		for i, p in ipairs(outline) do
			local r, h = p[1], p[2]
			ring[i] = {
				o[1] + u[1] * r * c + nx * ulen * r * sn + v[1] * h,
				o[2] + u[2] * r * c + ny * ulen * r * sn + v[2] * h,
				o[3] + u[3] * r * c + nz * ulen * r * sn + v[3] * h,
			}
		end
		point[s] = ring
	end

	local tris = {}
	local function triangle(a, b, c)
		local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
		local wx, wy, wz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
		local cx, cy, cz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
		if cx * cx + cy * cy + cz * cz < 1e-18 then
			return
		end
		tris[#tris + 1] = { a, b, c }
	end

	for s = 1, segments do
		local this, nxt = point[s], point[s % rings + 1]
		for i = 1, count do
			local j = i % count + 1
			local onI, onJ = outline[i][1] <= EPSILON, outline[j][1] <= EPSILON
			if not (onI and onJ) then
				if onI then
					triangle(this[i], this[j], nxt[j])
				elseif onJ then
					triangle(this[i], this[j], nxt[i])
				else
					triangle(this[i], this[j], nxt[j])
					triangle(this[i], nxt[j], nxt[i])
				end
			end
		end
	end
	if not full then
		for _, t in ipairs(Triangulate.polygon(outline)) do
			triangle(point[1][t[1]], point[1][t[3]], point[1][t[2]])
			triangle(point[rings][t[1]], point[rings][t[2]], point[rings][t[3]])
		end
	end

	-- Wind everything outward: the signed volume must be positive.
	local volume = 0
	for _, t in ipairs(tris) do
		local a, b, c = t[1], t[2], t[3]
		volume = volume + (a[1] * (b[2] * c[3] - b[3] * c[2]) - a[2] * (b[1] * c[3] - b[3] * c[1]) + a[3] * (b[1] * c[2] - b[2] * c[1]))
	end
	local flip = volume < 0

	local out = {}
	for _, t in ipairs(tris) do
		local a, b, c = t[1], t[2], t[3]
		if flip then
			b, c = c, b
		end
		local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
		local wx, wy, wz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
		local fx, fy, fz = unit(uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx)
		for _, p in ipairs({ a, b, c }) do
			out[#out + 1] = { x = p[1], y = p[2], z = p[3], nx = fx, ny = fy, nz = fz, r = color[1], g = color[2], b = color[3] }
		end
	end
	return out
end

return Lathe
