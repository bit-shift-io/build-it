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

return WorkPlaneView
