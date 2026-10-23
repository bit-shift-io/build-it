-- Primitive solids as triangle lists in the mesher's vertex format
-- (src/game/blocks/mesher.lua):
--   vertex = { x, y, z, nx, ny, nz, r, g, b, material }
-- every 3 vertices one triangle, wound so cross(b - a, c - a) points out.
-- Lengths are in tiles; x east, y south, z up. Pure; plain LuaJIT.
local Primitives = {}

local function vertex(p, n, color)
	return { x = p[1], y = p[2], z = p[3], nx = n[1], ny = n[2], nz = n[3], r = color[1], g = color[2], b = color[3] }
end

-- Unit-cube faces: outward normal and corners in outward winding order.
local BOX_FACES = {
	{ normal = { 0, 0, 1 }, corners = { { 0, 0, 1 }, { 1, 0, 1 }, { 1, 1, 1 }, { 0, 1, 1 } } },
	{ normal = { 0, 0, -1 }, corners = { { 0, 0, 0 }, { 0, 1, 0 }, { 1, 1, 0 }, { 1, 0, 0 } } },
	{ normal = { 1, 0, 0 }, corners = { { 1, 0, 0 }, { 1, 1, 0 }, { 1, 1, 1 }, { 1, 0, 1 } } },
	{ normal = { -1, 0, 0 }, corners = { { 0, 0, 0 }, { 0, 0, 1 }, { 0, 1, 1 }, { 0, 1, 0 } } },
	{ normal = { 0, 1, 0 }, corners = { { 0, 1, 0 }, { 0, 1, 1 }, { 1, 1, 1 }, { 1, 1, 0 } } },
	{ normal = { 0, -1, 0 }, corners = { { 0, 0, 0 }, { 1, 0, 0 }, { 1, 0, 1 }, { 0, 0, 1 } } },
}

-- A box from the origin to `size` ({ w, d, h }), in `color` ({ r, g, b }).
function Primitives.box(size, color)
	local out = {}
	for _, face in ipairs(BOX_FACES) do
		local p = {}
		for i, c in ipairs(face.corners) do
			p[i] = { c[1] * size[1], c[2] * size[2], c[3] * size[3] }
		end
		for _, i in ipairs({ 1, 2, 3, 1, 3, 4 }) do
			table.insert(out, vertex(p[i], face.normal, color))
		end
	end
	return out
end

-- A sphere of `radius` about the origin, smooth-shaded, in `color`, cut
-- into `segments` slices around the z axis (default 24; a multiple of 4
-- reaches its radius along x and y) and about half as many stacks pole to
-- pole (always even, so it has an equator).
function Primitives.sphere(radius, color, segments)
	local SEGMENTS = segments or 24
	local RINGS = math.max(2, 2 * math.floor(SEGMENTS / 4 + 0.5))
	local function point(ring, segment)
		local polar = math.pi * ring / RINGS
		local azimuth = 2 * math.pi * segment / SEGMENTS
		local n = { math.sin(polar) * math.cos(azimuth), math.sin(polar) * math.sin(azimuth), math.cos(polar) }
		return vertex({ n[1] * radius, n[2] * radius, n[3] * radius }, n, color)
	end
	local out = {}
	local function triangle(a, b, c)
		table.insert(out, a)
		table.insert(out, b)
		table.insert(out, c)
	end
	for ring = 0, RINGS - 1 do
		for segment = 0, SEGMENTS - 1 do
			-- Ring 0 is the top pole; going down and round eastward from +x.
			local a, b = point(ring, segment), point(ring, segment + 1)
			local c, d = point(ring + 1, segment), point(ring + 1, segment + 1)
			if ring > 0 then
				triangle(a, c, b)
			end
			if ring < RINGS - 1 then
				triangle(b, c, d)
			end
		end
	end
	return out
end

-- A wedge from the origin to `size` ({ w, d, h }), in `color`: a box
-- whose top slopes from full height on its west face down to the ground
-- along its east edge.
function Primitives.wedge(size, color)
	local w, d, h = size[1], size[2], size[3]
	local len = math.sqrt(w * w + h * h)
	local faces = {
		{ normal = { 0, 0, -1 }, corners = { { 0, 0, 0 }, { 0, d, 0 }, { w, d, 0 }, { w, 0, 0 } } },
		{ normal = { -1, 0, 0 }, corners = { { 0, 0, 0 }, { 0, 0, h }, { 0, d, h }, { 0, d, 0 } } },
		{ normal = { h / len, 0, w / len }, corners = { { 0, 0, h }, { w, 0, 0 }, { w, d, 0 }, { 0, d, h } } },
		{ normal = { 0, -1, 0 }, corners = { { 0, 0, 0 }, { w, 0, 0 }, { 0, 0, h } } },
		{ normal = { 0, 1, 0 }, corners = { { 0, d, 0 }, { 0, d, h }, { w, d, 0 } } },
	}
	local out = {}
	for _, face in ipairs(faces) do
		local order = #face.corners == 4 and { 1, 2, 3, 1, 3, 4 } or { 1, 2, 3 }
		for _, i in ipairs(order) do
			out[#out + 1] = vertex(face.corners[i], face.normal, color)
		end
	end
	return out
end

local function triangle(out, a, b, c)
	out[#out + 1] = a
	out[#out + 1] = b
	out[#out + 1] = c
end

-- A solid of revolution about the z axis from the ground up to `height`:
-- radius `bottom` at z = 0 narrowing (or not) to `top`, `segments` sides
-- round, the sides smooth-shaded and both ends capped (a zero radius end
-- is a point, no cap), so it is closed.
local function revolved(bottom, top, height, segments, color)
	local out = {}
	-- The side's outward normal at azimuth a: tilted up by how fast it narrows.
	local slope = bottom - top
	local len = math.sqrt(height * height + slope * slope)
	local function side(a, r, z)
		local c, s = math.cos(a), math.sin(a)
		return vertex({ r * c, r * s, z }, { c * height / len, s * height / len, slope / len }, color)
	end
	local function rim(a, r, z, n)
		return vertex({ r * math.cos(a), r * math.sin(a), z }, n, color)
	end
	for i = 0, segments - 1 do
		local a0, a1 = 2 * math.pi * i / segments, 2 * math.pi * (i + 1) / segments
		local mid = (a0 + a1) / 2
		if top > 0 then
			triangle(out, side(a0, bottom, 0), side(a1, bottom, 0), side(a1, top, height))
			triangle(out, side(a0, bottom, 0), side(a1, top, height), side(a0, top, height))
			triangle(out, vertex({ 0, 0, height }, { 0, 0, 1 }, color), rim(a0, top, height, { 0, 0, 1 }), rim(a1, top, height, { 0, 0, 1 }))
		else
			triangle(out, side(a0, bottom, 0), side(a1, bottom, 0), side(mid, 0, height))
		end
		triangle(out, vertex({ 0, 0, 0 }, { 0, 0, -1 }, color), rim(a1, bottom, 0, { 0, 0, -1 }), rim(a0, bottom, 0, { 0, 0, -1 }))
	end
	return out
end

-- A cylinder of `radius` about the z axis from the ground up to `height`,
-- `segments` sides round, in `color`.
function Primitives.cylinder(radius, height, segments, color)
	return revolved(radius, radius, height, segments, color)
end

-- A cone of base `radius` on the ground about the z axis, its point at
-- `height`, `segments` sides round, in `color`.
function Primitives.cone(radius, height, segments, color)
	return revolved(radius, 0, height, segments, color)
end

return Primitives
