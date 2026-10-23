-- 2D shapes (src/game/geometry/shape2d.lua): a shape's points -- hard
-- corners and smooth Bézier points -- tessellated to a closed outline,
-- wound counter-clockwise, and outlines that cross themselves rejected.
local Shape2d = require("src.game.geometry.shape2d")

-- The outline's corners as "x,y x,y ...".
local function corners(outline)
	local parts = {}
	for i, p in ipairs(outline) do
		parts[i] = p[1] .. "," .. p[2]
	end
	return table.concat(parts, " ")
end

test("hard points outline as themselves, a clockwise outline turned counter-clockwise", function()
	local ccw = assert(Shape2d.outline({ { 0, 0 }, { 2, 0 }, { 2, 1 }, { 0, 1 } }))
	assertEqual("0,0 2,0 2,1 0,1", corners(ccw))
	local cw = assert(Shape2d.outline({ { 0, 0 }, { 0, 1 }, { 2, 1 }, { 2, 0 } }))
	assertTrue(Shape2d.area(cw) > 0, "turned counter-clockwise")
	assertEqual(2, Shape2d.area(cw))
end)

test("a smooth point's sides tessellate as cubic Béziers through its mirrored handles", function()
	-- B (2,0) hard to C (1,2) smooth: P0 = P1 = B, P2 = C - h = (2,2), P3 = C;
	-- half way that is (15/8, 1).
	local outline = assert(Shape2d.outline({ { 0, 0 }, { 2, 0 }, { 1, 2, -1, 0 } }))
	assertEqual(1 + 2 * Shape2d.SEGMENTS, #outline)
	local found = false
	for _, p in ipairs(outline) do
		if math.abs(p[1] - 15 / 8) < 1e-9 and math.abs(p[2] - 1) < 1e-9 then
			found = true
		end
	end
	assertTrue(found, "the curve passes (15/8, 1): " .. corners(outline))
end)

test("an outline that crosses itself, has under 3 points or no area is rejected with why", function()
	local outline, why = Shape2d.outline({ { 0, 0 }, { 2, 2 }, { 2, 0 }, { 0, 2 } })
	assertEqual(nil, outline)
	assertEqual("outline crosses itself", why)
	-- A smooth point whose curve loops back over a straight side.
	assertEqual(nil, (Shape2d.outline({ { 0, 0 }, { 2, 0 }, { 1, 1, 0, -6 } })))
	assertEqual("needs at least 3 points", select(2, Shape2d.outline({ { 0, 0 }, { 1, 0 } })))
	assertEqual("outline has no area", select(2, Shape2d.outline({ { 0, 0 }, { 1, 0 }, { 2, 0 } })))
end)

test("a rect is four hard corners and an ellipse four smooth points, both from two opposite corners", function()
	local rect = Shape2d.rect({ 2, 1 }, { 0, 0 })
	assertEqual("0,0 2,0 2,1 0,1", corners(rect))
	local ellipse = Shape2d.ellipse({ 0, 0 }, { 4, 2 })
	assertEqual(4, #ellipse)
	assertEqual("4,1 2,2 0,1 2,0", corners(ellipse))
	local outline = assert(Shape2d.outline(ellipse))
	-- Close to the true ellipse's area, pi * 2 * 1.
	assertNear(math.pi * 2, Shape2d.area(outline), 0.05)
end)

test("an outline still being drawn traces open, as wound, ending on its last point", function()
	local open = Shape2d.trace({ { 0, 0 }, { 0, 1 }, { 2, 1 } }, true)
	assertEqual("0,0 0,1 2,1", corners(open))
	assertEqual(2 * Shape2d.SEGMENTS + 1, #Shape2d.trace({ { 0, 0 }, { 1, 0, 0, 1 }, { 1, 1 } }, true))
end)
