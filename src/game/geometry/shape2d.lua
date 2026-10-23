-- 2D shapes (docs/CONTEXT.md "Shape"): a closed outline on a work plane,
-- in the plane's own 2D coordinates (tiles). Pure; plain LuaJIT.
--
-- A shape is a list of points, each one hard or smooth:
--   { x, y }            a hard corner
--   { x, y, hx, hy }    a smooth point: its Bézier handle leaves it towards
--                       (x + hx, y + hy) and arrives from the mirror,
--                       (x - hx, y - hy)
-- The outline runs point to point and closes back to the first.
local Shape2d = {}

-- The outline's signed area: above 0 when it winds counter-clockwise.
function Shape2d.area(outline)
	local sum = 0
	for i, a in ipairs(outline) do
		local b = outline[i % #outline + 1]
		sum = sum + a[1] * b[2] - b[1] * a[2]
	end
	return sum / 2
end

-- How many straight pieces each curved side is cut into.
Shape2d.SEGMENTS = 8

-- Point p's handle: { hx, hy }, zero for a hard point.
local function handle(p)
	return p[3] or 0, p[4] or 0
end

-- The side from point a to point b appended to `out`, a included, b not.
local function side(a, b, out)
	out[#out + 1] = { a[1], a[2] }
	local ax, ay = handle(a)
	local bx, by = handle(b)
	if ax == 0 and ay == 0 and bx == 0 and by == 0 then
		return
	end
	local x1, y1 = a[1] + ax, a[2] + ay
	local x2, y2 = b[1] - bx, b[2] - by
	for i = 1, Shape2d.SEGMENTS - 1 do
		local t = i / Shape2d.SEGMENTS
		local s = 1 - t
		local w0, w1, w2, w3 = s * s * s, 3 * s * s * t, 3 * s * t * t, t * t * t
		out[#out + 1] = {
			w0 * a[1] + w1 * x1 + w2 * x2 + w3 * b[1],
			w0 * a[2] + w1 * y1 + w2 * y2 + w3 * b[2],
		}
	end
end

-- Which side of line a -> b point c is on: above 0 left, below 0 right.
local function orient(a, b, c)
	return (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1])
end

-- Whether c, on line a -> b, lies within the segment's box.
local function within(a, b, c)
	return math.min(a[1], b[1]) <= c[1] and c[1] <= math.max(a[1], b[1])
		and math.min(a[2], b[2]) <= c[2] and c[2] <= math.max(a[2], b[2])
end

-- Whether segments a -> b and c -> d meet, ends included.
local function meet(a, b, c, d)
	local o1, o2, o3, o4 = orient(a, b, c), orient(a, b, d), orient(c, d, a), orient(c, d, b)
	if ((o1 > 0 and o2 < 0) or (o1 < 0 and o2 > 0)) and ((o3 > 0 and o4 < 0) or (o3 < 0 and o4 > 0)) then
		return true
	end
	return (o1 == 0 and within(a, b, c)) or (o2 == 0 and within(a, b, d))
		or (o3 == 0 and within(c, d, a)) or (o4 == 0 and within(c, d, b))
end

-- Whether closed outline `outline` crosses or touches itself: two sides
-- that aren't neighbours meet, or a side folds straight back on the last.
local function crosses(outline)
	local n = #outline
	for i = 1, n do
		local a, b = outline[i], outline[i % n + 1]
		local c = outline[(i + 1) % n + 1]
		local folds = orient(a, b, c) == 0
			and (b[1] - a[1]) * (c[1] - b[1]) + (b[2] - a[2]) * (c[2] - b[2]) < 0
		if folds then
			return true
		end
		for j = i + 2, n do
			if not (i == 1 and j == n) and meet(a, b, outline[j], outline[j % n + 1]) then
				return true
			end
		end
	end
	return false
end

-- The corners along `points`, every side touching a smooth point cut into
-- Shape2d.SEGMENTS pieces, unchecked and as wound: round to the first
-- point again, or ending on the last when `open` (an outline still being
-- drawn).
function Shape2d.trace(points, open)
	local out = {}
	local n = #points
	for i = 1, open and n - 1 or n do
		side(points[i], points[i % n + 1], out)
	end
	if open and n > 0 then
		out[#out + 1] = { points[n][1], points[n][2] }
	end
	return out
end

-- Whether every corner of `outline` lies on one line.
local function flat(outline)
	local a, b = outline[1], nil
	for _, p in ipairs(outline) do
		if b then
			if orient(a, b, p) ~= 0 then
				return false
			end
		elseif p[1] ~= a[1] or p[2] ~= a[2] then
			b = p
		end
	end
	return true
end

-- The closed outline of `points`, as corners { { x, y }, ... } wound
-- counter-clockwise: every hard side straight, every side touching a
-- smooth point a cubic Bézier cut into Shape2d.SEGMENTS pieces. Nil and
-- why when it isn't a usable shape: under 3 points, no area, or crossing
-- itself.
function Shape2d.outline(points)
	if #points < 3 then
		return nil, "needs at least 3 points"
	end
	local out = Shape2d.trace(points)
	if flat(out) then
		return nil, "outline has no area"
	elseif crosses(out) then
		return nil, "outline crosses itself"
	end
	if Shape2d.area(out) < 0 then
		local n = #out
		for i = 1, math.floor(n / 2) do
			out[i], out[n + 1 - i] = out[n + 1 - i], out[i]
		end
	end
	return out
end

-- The box with opposite corners a and b ({ x, y } each): its least and
-- greatest x and y.
local function box(a, b)
	return math.min(a[1], b[1]), math.min(a[2], b[2]), math.max(a[1], b[1]), math.max(a[2], b[2])
end

-- The rect with opposite corners a and b: four hard points,
-- counter-clockwise from the least corner.
function Shape2d.rect(a, b)
	local x0, y0, x1, y1 = box(a, b)
	return { { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y1 } }
end

-- How far a quarter ellipse's handles reach, as a share of its radius.
local KAPPA = 4 * (math.sqrt(2) - 1) / 3

-- The ellipse filling the box with opposite corners a and b: four smooth
-- points, counter-clockwise from its east end.
function Shape2d.ellipse(a, b)
	local x0, y0, x1, y1 = box(a, b)
	local cx, cy, rx, ry = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2
	local kx, ky = rx * KAPPA, ry * KAPPA
	return {
		{ cx + rx, cy, 0, ky },
		{ cx, cy + ry, -kx, 0 },
		{ cx - rx, cy, 0, -ky },
		{ cx, cy - ry, kx, 0 },
	}
end

return Shape2d
