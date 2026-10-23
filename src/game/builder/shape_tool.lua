-- The Shape tool's game side (docs/CONTEXT.md "Shape", "Work plane"): an
-- outline drawn on the work plane made a shape node, and a closed shape's
-- points moved afterwards. Pure; plain LuaJIT.
--
-- Points are in the work plane's 2D coordinates, as
-- src/game/geometry/shape2d.lua takes them; the plane is
-- src/game/builder/work_plane.lua's { origin, u, v }.
local Shape2d = require("src.game.geometry.shape2d")
local Scene = require("src.game.builder.scene")

local ShapeTool = {}

-- What the tool draws, in its menu's order.
ShapeTool.KINDS = {
	{ label = "Rect", kind = "rect" },
	{ label = "Ellipse", kind = "ellipse" },
	{ label = "Polygon", kind = "polygon" },
	{ label = "Path", kind = "path" },
}

-- A shape node of `points` on `plane`, both copied, with no id (Scene.insert
-- gives it one); nil and why when the outline isn't a usable shape.
function ShapeTool.node(points, plane)
	local _, why = Shape2d.outline(points)
	if why then
		return nil, why
	end
	return {
		kind = "shape",
		points = Scene.copy(points),
		plane = Scene.copy(plane),
		transform = {},
	}
end

-- Scene edit: moves point `index` of shape `id` to plane coordinates
-- (a, b), its handle kept. Refused, with why, when the outline would no
-- longer be a usable shape.
function ShapeTool.movePoint(scene, id, index, a, b)
	local node = Scene.find(scene, id)
	if not node or node.kind ~= "shape" or not node.points[index] then
		return false, "no such point"
	end
	local points = Scene.copy(node.points)
	points[index][1], points[index][2] = a, b
	local _, why = Shape2d.outline(points)
	if why then
		return false, why
	end
	node.points = points
	return true
end

return ShapeTool
