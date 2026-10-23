-- The builder's transform gizmo (docs/CONTEXT.md "Builder"): a handle per
-- axis on the selection's centre, drawn over the 3D view. For move and
-- scale each handle is a line out along its axis, for rotate a ring about
-- it. Dragging a handle runs that transform held to its axis
-- (src/app/screens/script_builder.lua).
--
-- Handles are projected through the builder camera (src/app/builder_camera.lua),
-- never the world's Projection, and their layout and hit test are pure
-- arithmetic; only Gizmo.draw calls love.*.
local BuilderCamera = require("src.app.builder_camera")

local Gizmo = {}

-- A handle's reach from the centre, in tiles.
Gizmo.LENGTH = 1.25
-- How near the pointer must come to a handle to grab it, in pixels.
local GRAB = 8
-- Points around a rotate ring.
local RING_POINTS = 32

local COLORS = { x = { 0.95, 0.3, 0.3 }, y = { 0.35, 0.85, 0.35 }, z = { 0.35, 0.55, 1 } }
local ACTIVE_COLOR = { 1, 0.9, 0.3 }
local AXES = { "x", "y", "z" }
local DIRECTIONS = { x = { 1, 0, 0 }, y = { 0, 1, 0 }, z = { 0, 0, 1 } }
-- The two axes a ring about each axis spans.
local RING_SPAN = { x = { "y", "z" }, y = { "z", "x" }, z = { "x", "y" } }

-- The handles for transform `mode` about `centre` (tiles, the view's
-- space) through `view` (studs, studsPerTile `s` to a tile):
-- { { axis, points = { x1, y1, x2, y2, ... } }, ... } in screen pixels.
-- Points behind the camera are left out.
function Gizmo.handles(view, centre, s, mode)
	local out = {}
	for _, axis in ipairs(AXES) do
		local along = {}
		if mode == "rotate" then
			local u, v = DIRECTIONS[RING_SPAN[axis][1]], DIRECTIONS[RING_SPAN[axis][2]]
			for i = 0, RING_POINTS do
				local a = i / RING_POINTS * 2 * math.pi
				local c, sn = math.cos(a) * Gizmo.LENGTH, math.sin(a) * Gizmo.LENGTH
				along[#along + 1] = { u[1] * c + v[1] * sn, u[2] * c + v[2] * sn, u[3] * c + v[3] * sn }
			end
		else
			local d = DIRECTIONS[axis]
			along = { { 0, 0, 0 }, { d[1] * Gizmo.LENGTH, d[2] * Gizmo.LENGTH, d[3] * Gizmo.LENGTH } }
		end
		local points = {}
		for _, p in ipairs(along) do
			local sx, sy, _, depth = BuilderCamera.project(view, (centre[1] + p[1]) * s, (centre[2] + p[2]) * s, (centre[3] + p[3]) * s)
			if depth > view.near then
				points[#points + 1] = sx
				points[#points + 1] = sy
			end
		end
		out[#out + 1] = { axis = axis, points = points }
	end
	return out
end

-- Distance from (px, py) to the segment (ax, ay)-(bx, by).
local function toSegment(px, py, ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	local len = dx * dx + dy * dy
	local t = len > 0 and math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / len)) or 0
	local x, y = ax + dx * t, ay + dy * t
	return math.sqrt((px - x) ^ 2 + (py - y) ^ 2)
end

-- The axis of the handle nearest screen point (x, y) within grabbing
-- reach, or nil.
function Gizmo.handleAt(handles, x, y)
	local best, nearest = nil, GRAB
	for _, h in ipairs(handles) do
		local p = h.points
		for i = 1, #p - 3, 2 do
			local d = toSegment(x, y, p[i], p[i + 1], p[i + 2], p[i + 3])
			if d <= nearest then
				best, nearest = h.axis, d
			end
		end
	end
	return best
end

-- Draws `handles`, the one on axis `active` highlighted.
function Gizmo.draw(handles, active)
	love.graphics.push("all")
	love.graphics.setLineWidth(3)
	for _, h in ipairs(handles) do
		if #h.points >= 4 then
			love.graphics.setColor(h.axis == active and ACTIVE_COLOR or COLORS[h.axis])
			love.graphics.line(h.points)
			love.graphics.circle("fill", h.points[#h.points - 1], h.points[#h.points], 4)
		end
	end
	love.graphics.pop()
end

return Gizmo
