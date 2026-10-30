-- The work plane's grid (docs/CONTEXT.md "Work plane"), drawn over the
-- builder's 3D view (src/app/screens/script_builder.lua): faint quarter
-- tile lines, stronger whole-tile ones. Lines come from WorkPlane.grid in
-- design space and are projected through the builder camera
-- (src/app/builder_camera.lua), never the world's Projection.
local BuilderCamera = require("src.app.builder_camera")

local WorkPlaneView = {}

local MINOR_COLOR = { 1, 1, 1, 0.12 }
local MAJOR_COLOR = { 1, 1, 1, 0.3 }

-- The screen pixel of design-space point p through `view` (studs, `s` to a
-- tile; the blueprint's space starts at design-space `origin`), or nil
-- when it is behind the camera.
function WorkPlaneView.pixel(view, s, origin, p)
	local sx, sy, _, depth = BuilderCamera.project(view, (p[1] - origin[1]) * s, (p[2] - origin[2]) * s, p[3] * s)
	if depth <= view.near then
		return nil
	end
	return sx, sy
end

-- Draws grid `lines` (WorkPlane.grid); a line with an end behind the camera
-- is left out.
function WorkPlaneView.draw(view, s, origin, lines)
	love.graphics.push("all")
	love.graphics.setLineWidth(1)
	for _, line in ipairs(lines) do
		local ax, ay = WorkPlaneView.pixel(view, s, origin, line[1])
		local bx, by = WorkPlaneView.pixel(view, s, origin, line[2])
		if ax and bx then
			love.graphics.setColor(line.major and MAJOR_COLOR or MINOR_COLOR)
			love.graphics.line(ax, ay, bx, by)
		end
	end
	love.graphics.pop()
end

local GUIDE_COLOR = { 1, 1, 1, 0.6 }
local AXES = {
	{ { 1, 0, 0 }, { 0.9, 0.2, 0.2, 1 } }, -- X, east
	{ { 0, 1, 0 }, { 0.3, 0.8, 0.3, 1 } }, -- Y, south
	{ { 0, 0, 1 }, { 0.3, 0.5, 1, 1 } }, -- Z, up
}

-- Draws the always-on ground reference round the design's origin: the
-- whole-tile `lines` (WorkPlane.groundGrid), a 1x1 tile outline at the
-- origin and an axis arm of one tile each, X red, Y green, Z blue.
function WorkPlaneView.drawGround(view, s, origin, lines)
	WorkPlaneView.draw(view, s, origin, lines)
	love.graphics.push("all")
	love.graphics.setLineWidth(2)
	local corners = { { 0, 0, 0 }, { 1, 0, 0 }, { 1, 1, 0 }, { 0, 1, 0 } }
	local pts = {}
	for _, c in ipairs(corners) do
		local x, y = WorkPlaneView.pixel(view, s, origin, c)
		if not x then
			pts = nil
			break
		end
		pts[#pts + 1] = x
		pts[#pts + 1] = y
	end
	if pts then
		love.graphics.setColor(GUIDE_COLOR)
		love.graphics.polygon("line", pts)
	end
	for _, axis in ipairs(AXES) do
		local ax, ay = WorkPlaneView.pixel(view, s, origin, { 0, 0, 0 })
		local bx, by = WorkPlaneView.pixel(view, s, origin, axis[1])
		if ax and bx then
			love.graphics.setColor(axis[2])
			love.graphics.line(ax, ay, bx, by)
		end
	end
	love.graphics.pop()
end

return WorkPlaneView
