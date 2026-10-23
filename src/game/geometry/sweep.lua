-- Sweep (docs/CONTEXT.md "Operation"): a shape carried along a path into a
-- closed solid. Pure; plain LuaJIT.
--
-- The path's points (src/game/geometry/path.lua) are joined by straight
-- chords. Each chord carries a frame { t (along it), n, b } turned from the
-- chord before by the least rotation that lines its t up: a rotation-
-- minimising frame, so the profile never flips or spins of its own accord.
-- The first frame's b is the design's up, as near as the path allows.
--
-- The profile is the shape's outline in its own 2D coordinates, centred on
-- its bounds: a runs along n, b along the frame's b. At each point it is
-- turned by twist and scaled, both growing linearly with the distance
-- along the path, then mitred: laid where the chord before meets the plane
-- halving the corner, so walls meet at hard points. Both ends are capped.
local Shape2d = require("src.game.geometry.shape2d")
local Triangulate = require("src.game.geometry.triangulate")

local Sweep = {}

local function dot(a, b)
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

local function cross(a, b)
	return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end

local function sub(a, b)
	return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end

local function scaled(a, s)
	return { a[1] * s, a[2] * s, a[3] * s }
end

local function unit(a)
	local len = math.sqrt(dot(a, a))
	return { a[1] / len, a[2] / len, a[3] / len }, len
end

-- `a` with its part along unit `t` taken away.
local function off(a, t)
	return sub(a, scaled(t, dot(a, t)))
end

-- Vector `v` turned about unit `axis` by the angle whose cosine and sine
-- are c and s (Rodrigues).
local function turned(v, axis, c, s)
	local k = cross(axis, v)
	local d = dot(axis, v) * (1 - c)
	return { v[1] * c + k[1] * s + axis[1] * d, v[2] * c + k[2] * s + axis[2] * d, v[3] * c + k[3] * s + axis[3] * d }
end

-- The frames of the chords between `points` ({ { x, y, z }, ... }, no two
-- in a row the same): { { t, n, b }, ... }, one per chord, each a right-
-- handed unit set (b = t x n).
function Sweep.frames(points)
	local frames = {}
	for i = 1, #points - 1 do
		local t = unit(sub(points[i + 1], points[i]))
		local n
		if i == 1 then
			local up, len = unit(off({ 0, 0, 1 }, t))
			if not (len > 1e-6) then
				up = unit(off({ 0, -1, 0 }, t))
			end
			n = cross(up, t)
		else
			local before = frames[i - 1]
			local axis, s = unit(cross(before.t, t))
			n = before.n
			if s > 1e-12 then
				n = turned(n, axis, dot(before.t, t), s)
			end
			n = unit(off(n, t))
		end
		frames[i] = { t = t, n = n, b = cross(t, n) }
	end
	return frames
end

-- `points` without any point the same as the one before it.
local function distinct(points)
	local out = {}
	for _, p in ipairs(points) do
		local last = out[#out]
		if not last or p[1] ~= last[1] or p[2] ~= last[2] or p[3] ~= last[3] then
			out[#out + 1] = p
		end
	end
	return out
end

-- The outline of `shape` (src/game/geometry/shape2d.lua), counter-clockwise,
-- moved so its bounds are centred on (0, 0); nil when it isn't usable.
local function profile(shape)
	local outline = Shape2d.outline(shape.points)
	if not outline then
		return nil
	end
	local inf = math.huge
	local x0, y0, x1, y1 = inf, inf, -inf, -inf
	for _, p in ipairs(outline) do
		x0, y0 = math.min(x0, p[1]), math.min(y0, p[2])
		x1, y1 = math.max(x1, p[1]), math.max(y1, p[2])
	end
	local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
	local out = {}
	for i, p in ipairs(outline) do
		out[i] = { p[1] - cx, p[2] - cy }
	end
	return out
end

-- The share of the way along `points` each one lies, by length.
local function shares(points)
	local out, total = { 0 }, 0
	for i = 2, #points do
		local _, len = unit(sub(points[i], points[i - 1]))
		total = total + len
		out[i] = total
	end
	for i = 1, #out do
		out[i] = out[i] / total
	end
	return out
end

-- The profile's corners in design space at every point along `points`
-- (distinct, at least two): { { { x, y, z }, ... }, ... }, one ring per
-- point, each laid on its frame, twisted, scaled and mitred (see the top
-- of this file). opts = { twist (degrees over the whole path, 0),
-- startScale (1), endScale (1) }.
function Sweep.rings(outline, points, opts)
	local frames = Sweep.frames(points)
	local along = shares(points)
	local twist = math.rad(opts.twist or 0)
	local s0, s1 = opts.startScale or 1, opts.endScale or 1
	local rings = {}
	for k, x in ipairs(points) do
		local f = frames[math.max(1, k - 1)]
		local c, s = math.cos(twist * along[k]), math.sin(twist * along[k])
		local size = s0 + (s1 - s0) * along[k]
		-- The plane halving the corner at an inner point, when it has one.
		local mitre, lean = nil, nil
		if k > 1 and k < #points then
			local m, len = unit({ f.t[1] + frames[k].t[1], f.t[2] + frames[k].t[2], f.t[3] + frames[k].t[3] })
			if len > 1e-9 then
				mitre, lean = m, dot(f.t, m)
			end
		end
		local ring = {}
		for i, p in ipairs(outline) do
			local a = size * (p[1] * c - p[2] * s)
			local b = size * (p[1] * s + p[2] * c)
			local q = { x[1] + a * f.n[1] + b * f.b[1], x[2] + a * f.n[2] + b * f.b[2], x[3] + a * f.n[3] + b * f.b[3] }
			if mitre then
				q = sub(q, scaled(f.t, dot(sub(q, x), mitre) / lean))
			end
			ring[i] = q
		end
		rings[k] = ring
	end
	return rings
end

-- The solid of `shape` ({ points }, its outline as the profile) swept
-- along `points` (Path.points, in the sweep's space) with `opts` (as
-- Sweep.rings): walls between each ring and the next and a cap at each
-- end, every edge shared by two triangles, wound outward. Triangles as in
-- src/game/geometry/primitives.lua, in `color`; empty when the shape or
-- path is unusable.
function Sweep.mesh(shape, points, opts, color)
	local outline = profile(shape)
	points = distinct(points)
	if not outline or #points < 2 then
		return {}
	end
	local rings = Sweep.rings(outline, points, opts)
	local out = {}
	local function triangle(a, b, c)
		local n, len = unit(cross(sub(b, a), sub(c, a)))
		if not (len > 0) then
			n = { 0, 0, 1 }
		end
		for _, p in ipairs({ a, b, c }) do
			out[#out + 1] = { x = p[1], y = p[2], z = p[3], nx = n[1], ny = n[2], nz = n[3], r = color[1], g = color[2], b = color[3] }
		end
	end
	local count = #outline
	for k = 1, #rings - 1 do
		local bottom, top = rings[k], rings[k + 1]
		for i = 1, count do
			local j = i % count + 1
			triangle(bottom[i], bottom[j], top[j])
			triangle(bottom[i], top[j], top[i])
		end
	end
	local first, last = rings[1], rings[#rings]
	for _, t in ipairs(Triangulate.polygon(outline)) do
		triangle(first[t[1]], first[t[3]], first[t[2]])
		triangle(last[t[1]], last[t[2]], last[t[3]])
	end
	return out
end

return Sweep
