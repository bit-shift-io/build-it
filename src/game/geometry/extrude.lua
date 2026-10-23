-- Extrude (docs/CONTEXT.md "Operation"): a shape pushed along its work
-- plane's normal into a closed solid. Pure; plain LuaJIT.
local Shape2d = require("src.game.geometry.shape2d")
local Triangulate = require("src.game.geometry.triangulate")

local Extrude = {}

local function unit(x, y, z)
	local len = math.sqrt(x * x + y * y + z * z)
	return x / len, y / len, z / len
end

-- The solid of `shape` ({ points, plane = { origin, u, v } }) pushed
-- `height` tiles along the plane's normal (u x v), in the shape's own
-- space: two ear-clipped caps and a wall along every side, every edge
-- shared by two triangles. Triangles as in src/game/geometry/primitives.lua,
-- in `color`; empty when the outline is unusable.
function Extrude.mesh(shape, height, color)
	local outline = Shape2d.outline(shape.points)
	if not outline then
		return {}
	end
	local o, u, v = shape.plane.origin, shape.plane.u, shape.plane.v
	local nx, ny, nz = unit(u[2] * v[3] - u[3] * v[2], u[3] * v[1] - u[1] * v[3], u[1] * v[2] - u[2] * v[1])
	local bottom, top = {}, {}
	for i, p in ipairs(outline) do
		local x = o[1] + p[1] * u[1] + p[2] * v[1]
		local y = o[2] + p[1] * u[2] + p[2] * v[2]
		local z = o[3] + p[1] * u[3] + p[2] * v[3]
		bottom[i] = { x, y, z }
		top[i] = { x + nx * height, y + ny * height, z + nz * height }
	end
	local out = {}
	local function triangle(a, b, c, n)
		for _, p in ipairs({ a, b, c }) do
			out[#out + 1] = { x = p[1], y = p[2], z = p[3], nx = n[1], ny = n[2], nz = n[3], r = color[1], g = color[2], b = color[3] }
		end
	end
	local up, down = { nx, ny, nz }, { -nx, -ny, -nz }
	for _, t in ipairs(Triangulate.polygon(outline)) do
		triangle(top[t[1]], top[t[2]], top[t[3]], up)
		triangle(bottom[t[1]], bottom[t[3]], bottom[t[2]], down)
	end
	local count = #outline
	for i = 1, count do
		local j = i % count + 1
		local ex, ey, ez = bottom[j][1] - bottom[i][1], bottom[j][2] - bottom[i][2], bottom[j][3] - bottom[i][3]
		-- Outward is the side direction crossed with the normal.
		local wall = { unit(ey * nz - ez * ny, ez * nx - ex * nz, ex * ny - ey * nx) }
		triangle(bottom[i], bottom[j], top[j], wall)
		triangle(bottom[i], top[j], top[i], wall)
	end
	return out
end

return Extrude
