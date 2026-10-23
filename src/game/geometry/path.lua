-- Paths (docs/CONTEXT.md "Path"): the open curves a shape is swept along,
-- sampled to points. Pure; plain LuaJIT.
--
-- A path lies on a work plane { origin, u, v } (src/game/builder/work_plane.lua),
-- its 2D coordinates (a, b) at origin + a * u + b * v, and is one of:
--   line       points = { p1, p2 }
--   polyline   points = { p1, p2, ... }, straight between them
--   bezier     points as src/game/geometry/shape2d.lua takes them (hard
--              { x, y } or smooth { x, y, hx, hy }), left open
--   catmull    points = { p1, p2, ... }, a Catmull-Rom spline through them
--   arc        centre = { a, b }, radius, start and angle (degrees, counter-
--              clockwise from u): from start round to start + angle
--   helix      centre = { a, b }, radius, turns, pitch: round from u,
--              climbing pitch per turn along the plane's normal u x v
local Shape2d = require("src.game.geometry.shape2d")

local Path = {}

-- The curves a path can be, in the Path tool's order, and as a set.
Path.CURVE_NAMES = { "line", "polyline", "bezier", "catmull", "arc", "helix" }
Path.CURVES = {}
for _, name in ipairs(Path.CURVE_NAMES) do
	Path.CURVES[name] = true
end

-- How many straight pieces a full turn of an arc or helix is cut into.
Path.SEGMENTS_PER_TURN = 32

-- How many straight pieces each curved span of a Bézier or Catmull-Rom
-- path is cut into.
Path.SEGMENTS = Shape2d.SEGMENTS

-- Design-space point (a, b) of `plane`, raised h along its normal u x v.
local function at(plane, a, b, h)
	local o, u, v = plane.origin, plane.u, plane.v
	local nx, ny, nz = u[2] * v[3] - u[3] * v[2], u[3] * v[1] - u[1] * v[3], u[1] * v[2] - u[2] * v[1]
	h = h or 0
	return {
		o[1] + a * u[1] + b * v[1] + h * nx,
		o[2] + a * u[2] + b * v[2] + h * ny,
		o[3] + a * u[3] + b * v[3] + h * nz,
	}
end

-- Points round `centre` at `radius` from `start` through `angle` (both
-- radians) on `plane`, climbing `rise` over the whole way.
local function round(plane, centre, radius, start, angle, rise)
	local turns = math.abs(angle) / (2 * math.pi)
	local count = math.max(1, math.ceil(turns * Path.SEGMENTS_PER_TURN - 1e-9))
	local out = {}
	for i = 0, count do
		local f = i / count
		local phi = start + angle * f
		out[#out + 1] = at(plane, centre[1] + radius * math.cos(phi), centre[2] + radius * math.sin(phi), rise * f)
	end
	return out
end

-- The uniform Catmull-Rom spline through `points` ({ { a, b }, ... }),
-- each span cut into Path.SEGMENTS pieces, the end points doubled so it
-- starts and ends on them.
local function catmull(points)
	local n = #points
	local out = {}
	for i = 1, n - 1 do
		local p0, p1 = points[math.max(1, i - 1)], points[i]
		local p2, p3 = points[i + 1], points[math.min(n, i + 2)]
		for k = 0, Path.SEGMENTS - 1 do
			local t = k / Path.SEGMENTS
			local t2, t3 = t * t, t * t * t
			local p = {}
			for c = 1, 2 do
				p[c] = 0.5 * (2 * p1[c] + (p2[c] - p0[c]) * t
					+ (2 * p0[c] - 5 * p1[c] + 4 * p2[c] - p3[c]) * t2
					+ (-p0[c] + 3 * p1[c] - 3 * p2[c] + p3[c]) * t3)
			end
			out[#out + 1] = p
		end
	end
	out[#out + 1] = { points[n][1], points[n][2] }
	return out
end

-- The design-space points along path `node` (the fields above), in its
-- own space (its transform not applied), start to end; nil and why when
-- it isn't a usable path.
function Path.points(node)
	local plane = node.plane
	if node.curve == "helix" then
		return round(plane, node.centre, node.radius, 0, 2 * math.pi * node.turns, node.pitch * node.turns)
	elseif node.curve == "arc" then
		return round(plane, node.centre, node.radius, math.rad(node.start), math.rad(node.angle), 0)
	end
	local flat
	if node.curve == "line" or node.curve == "polyline" or node.curve == "bezier" then
		flat = Shape2d.trace(node.points, true)
	elseif node.curve == "catmull" then
		flat = catmull(node.points)
	else
		return nil, "unknown curve " .. tostring(node.curve)
	end
	local out = {}
	for i, p in ipairs(flat) do
		out[i] = at(plane, p[1], p[2])
	end
	return out
end

return Path
