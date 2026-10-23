-- The Shape tool's game side (src/game/builder/shape_tool.lua): a drawn
-- outline made a shape node on its work plane, and a closed shape's
-- points moved afterwards as scene edits.
local Sandbox = require("src.game.script.sandbox")
local Scene = require("src.game.builder.scene")
local ShapeTool = require("src.game.builder.shape_tool")
local WorkPlane = require("src.game.builder.work_plane")

test("drawn points become a shape node on a copy of the work plane; a bad outline is refused", function()
	local plane = WorkPlane.axis("XZ", 1)
	local points = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } }
	local node = assert(ShapeTool.node(points, plane))
	assertEqual("shape", node.kind)
	assertEqual(4, #node.points)
	assertEqual("1 0", table.concat(node.points[2], " "))
	assertEqual("0 1 0", table.concat(node.plane.origin, " "))
	assertTrue(node.plane ~= plane and node.points ~= points, "copies, not the drawing's tables")
	local none, why = ShapeTool.node({ { 0, 0 }, { 1, 1 }, { 1, 0 }, { 0, 1 } }, plane)
	assertEqual(nil, none)
	assertEqual("outline crosses itself", why)
end)

test("moving a closed shape's point keeps its handle, and a move that crosses the outline is refused", function()
	local scene = Scene.new(assert(Sandbox.run([[
return group{ id = "root", shape{ id = "s", points = { { 0, 0 }, { 2, 0 }, { 2, 2, 0, 0.5 }, { 0, 2 } } } }
]], "design")).root)
	assertTrue(ShapeTool.movePoint(scene, "s", 3, 3, 2.5))
	local s = Scene.find(scene, "s")
	assertEqual("3 2.5 0 0.5", table.concat(s.points[3], " "))
	local ok, why = ShapeTool.movePoint(scene, "s", 1, 3, 3)
	assertFalse(ok)
	assertEqual("outline crosses itself", why)
	assertEqual("0 0", table.concat(s.points[1], " "), "refused move left it")
end)
