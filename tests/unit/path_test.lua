-- Paths (src/game/geometry/path.lua): the curves a shape sweeps along --
-- line, polyline, Bézier, Catmull-Rom, arc and helix -- sampled to points
-- in design space on their work plane.
local Path = require("src.game.geometry.path")

local GROUND = { origin = { 0, 0, 0 }, u = { 1, 0, 0 }, v = { 0, 1, 0 } }

test("a helix climbs pitch per turn round its centre at its radius", function()
	local points = assert(Path.points({ curve = "helix", plane = GROUND, centre = { 1, 2 }, radius = 0.5, turns = 2, pitch = 1.5 }))
	assertEqual(2 * Path.SEGMENTS_PER_TURN + 1, #points)
	for i, p in ipairs(points) do
		local turned = (i - 1) / Path.SEGMENTS_PER_TURN
		local angle = 2 * math.pi * turned
		assertNear(1 + 0.5 * math.cos(angle), p[1], 1e-9)
		assertNear(2 + 0.5 * math.sin(angle), p[2], 1e-9)
		assertNear(1.5 * turned, p[3], 1e-9)
	end
end)

test("an arc runs from start through angle at its radius, on its plane", function()
	-- The XZ plane at y = 3: a is x, b is z.
	local plane = { origin = { 0, 3, 0 }, u = { 1, 0, 0 }, v = { 0, 0, 1 } }
	local points = assert(Path.points({ curve = "arc", plane = plane, centre = { 0, 1 }, radius = 2, start = 90, angle = -90 }))
	assertEqual(Path.SEGMENTS_PER_TURN / 4 + 1, #points)
	local first, last = points[1], points[#points]
	assertNear(0, first[1], 1e-9)
	assertNear(3, first[2], 1e-9)
	assertNear(3, first[3], 1e-9)
	assertNear(2, last[1], 1e-9)
	assertNear(1, last[3], 1e-9)
	for _, p in ipairs(points) do
		assertNear(2, math.sqrt(p[1] ^ 2 + (p[3] - 1) ^ 2), 1e-9)
	end
end)

local function listed(points)
	local parts = {}
	for i, p in ipairs(points) do
		parts[i] = p[1] .. "," .. p[2] .. "," .. p[3]
	end
	return table.concat(parts, " ")
end

test("a line and a polyline run straight through their points, left open", function()
	local raised = { origin = { 0, 0, 2 }, u = { 1, 0, 0 }, v = { 0, 1, 0 } }
	assertEqual("0,0,2 3,1,2", listed(assert(Path.points({ curve = "line", plane = raised, points = { { 0, 0 }, { 3, 1 } } }))))
	local poly = { { 0, 0 }, { 2, 0 }, { 2, 2 }, { 0, 2 } }
	assertEqual("0,0,0 2,0,0 2,2,0 0,2,0", listed(assert(Path.points({ curve = "polyline", plane = GROUND, points = poly }))))
end)

test("a Bézier path curves through its smooth points' handles and stays open", function()
	-- (0,0) smooth, handle (1,0) -> (2,2) hard: P0 (0,0), P1 (1,0), P2 = P3 = (2,2).
	local points = assert(Path.points({ curve = "bezier", plane = GROUND, points = { { 0, 0, 1, 0 }, { 2, 2 } } }))
	assertEqual(Path.SEGMENTS + 1, #points)
	local half = points[Path.SEGMENTS / 2 + 1]
	-- t = 1/2: (0 + 3 * 1 + 3 * 2 + 2) / 8, (0 + 0 + 3 * 2 + 2) / 8
	assertNear(11 / 8, half[1], 1e-9)
	assertNear(1, half[2], 1e-9)
	assertEqual("2,2,0", listed({ points[#points] }))
end)

test("a Catmull-Rom path passes through every point, its ends included", function()
	local through = { { 0, 0 }, { 1, 1 }, { 3, 1 }, { 4, 0 } }
	local points = assert(Path.points({ curve = "catmull", plane = GROUND, points = through }))
	assertEqual(3 * Path.SEGMENTS + 1, #points)
	for i, p in ipairs(through) do
		local sample = points[(i - 1) * Path.SEGMENTS + 1]
		assertNear(p[1], sample[1], 1e-9)
		assertNear(p[2], sample[2], 1e-9)
	end
	-- Uniform Catmull-Rom half way from (1,1) to (3,1): 
	-- 0.5 * (2 P1 + (P2 - P0) t + (2P0 - 5P1 + 4P2 - P3) t^2 + (-P0 + 3P1 - 3P2 + P3) t^3)
	local mid = points[Path.SEGMENTS + Path.SEGMENTS / 2 + 1]
	assertNear(2, mid[1], 1e-9)
	assertNear(1.125, mid[2], 1e-9)
end)
