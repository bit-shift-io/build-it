-- The Path tool's game side (docs/CONTEXT.md "Path", "Work plane"): the
-- clicks on the work plane made a path node of the curve picked. Pure;
-- plain LuaJIT.
--
-- Clicks are in the work plane's 2D coordinates, as
-- src/game/geometry/path.lua takes them; the plane is
-- src/game/builder/work_plane.lua's { origin, u, v }.
local Scene = require("src.game.builder.scene")

local PathTool = {}

-- What the tool draws, in its menu's order.
PathTool.KINDS = {
	{ label = "Line", curve = "line" },
	{ label = "Polyline", curve = "polyline" },
	{ label = "Bezier", curve = "bezier" },
	{ label = "Catmull-Rom", curve = "catmull" },
	{ label = "Arc", curve = "arc" },
	{ label = "Helix", curve = "helix" },
}

-- How many clicks finish a curve that takes a set number; the others take
-- any number from 2 and finish when told.
PathTool.CLICKS = { line = 2, arc = 3, helix = 2 }

-- `x` to a millionth, so angles worked out from the grid read back short.
local function tidy(x)
	return math.floor(x * 1e6 + 0.5) / 1e6
end

-- Where (a, b) lies from `centre`: its distance and its angle in degrees
-- counter-clockwise from u.
local function polar(centre, p)
	local da, db = p[1] - centre[1], p[2] - centre[2]
	return math.sqrt(da * da + db * db), math.deg(math.atan2(db, da))
end

-- A path node of `curve` (a PathTool.KINDS curve) from `clicks` on
-- `plane`, both copied, with no id (Scene.insert gives it one); nil and
-- why when the clicks don't make one.
--   line, polyline, catmull   the clicks are its points
--   bezier                    the clicks are its points, handles kept
--   arc                       centre, start, end: round counter-clockwise
--   helix                     centre, then a point at its radius; one turn
--                             climbing one tile
function PathTool.node(curve, clicks, plane)
	local node = { kind = "path", curve = curve, plane = Scene.copy(plane), transform = {} }
	if curve == "arc" or curve == "helix" then
		if #clicks < PathTool.CLICKS[curve] then
			return nil, "not enough points"
		end
		local centre = { clicks[1][1], clicks[1][2] }
		local radius, start = polar(centre, clicks[2])
		if radius == 0 then
			return nil, "the radius is 0"
		end
		node.centre, node.radius = centre, radius
		if curve == "helix" then
			node.turns, node.pitch = 1, 1
			return node
		end
		local _, finish = polar(centre, clicks[3])
		local angle = tidy((finish - start) % 360)
		node.start, node.angle = tidy(start), angle == 0 and 360 or angle
		return node
	end
	local points = {}
	for i, p in ipairs(clicks) do
		points[i] = curve == "bezier" and Scene.copy(p) or { p[1], p[2] }
		if curve == "line" and i == 2 then
			break
		end
	end
	for i = 2, #points do
		if points[i][1] ~= points[1][1] or points[i][2] ~= points[1][2] then
			node.points = points
			return node
		end
	end
	return nil, "needs 2 different points"
end

return PathTool
