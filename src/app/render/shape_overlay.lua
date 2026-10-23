-- Shapes and paths in the builder (docs/CONTEXT.md "Shape", "Path"):
-- outlines and open curves with no volume, drawn over the 3D view -- every
-- shape's and path's, the selected ones brighter, the selected shape's
-- points and Bézier handles, and the outline or path being drawn. What to draw comes from ScriptBuilderScreen.overlay
-- in design space; points project through the builder camera.
local WorkPlaneView = require("src.app.render.work_plane")

local ShapeOverlay = {}

local OUTLINE_COLOR = { 0.95, 0.85, 0.4, 0.8 }
local SELECTED_COLOR = { 1, 0.65, 0.2, 1 }
local DRAWING_COLOR = { 0.5, 0.85, 1, 1 }
local POINT_COLOR = { 1, 1, 1, 1 }
local HANDLE_COLOR = { 0.5, 0.85, 1, 0.9 }
local POINT_SIZE = 4

-- `corners` as screen pixels { x1, y1, x2, y2, ... }, the first again at
-- the end when `closed`; nil when any lies behind the camera.
local function pixels(view, s, origin, corners, closed)
	local out = {}
	for _, p in ipairs(corners) do
		local x, y = WorkPlaneView.pixel(view, s, origin, p)
		if not x then
			return nil
		end
		out[#out + 1], out[#out + 2] = x, y
	end
	if closed and #out >= 2 then
		out[#out + 1], out[#out + 2] = out[1], out[2]
	end
	return out
end

local function polyline(view, s, origin, corners, closed)
	local line = pixels(view, s, origin, corners, closed)
	if line and #line >= 4 then
		love.graphics.line(line)
	end
end

-- Draws `overlay` ({ outlines, points, drawing }, ScriptBuilderScreen.overlay;
-- a path is an outline that isn't closed)
-- through `view` (studs, `s` to a tile, the blueprint's space starting at
-- design-space `origin`).
function ShapeOverlay.draw(view, s, origin, overlay)
	love.graphics.push("all")
	love.graphics.setLineWidth(2)
	for _, o in ipairs(overlay.outlines) do
		love.graphics.setColor(o.selected and SELECTED_COLOR or OUTLINE_COLOR)
		polyline(view, s, origin, o.corners, o.closed)
	end
	if overlay.drawing then
		love.graphics.setColor(DRAWING_COLOR)
		polyline(view, s, origin, overlay.drawing.corners, overlay.drawing.closed)
	end
	love.graphics.setLineWidth(1)
	for _, p in ipairs(overlay.points) do
		local x, y = WorkPlaneView.pixel(view, s, origin, p.at)
		if x then
			for _, h in ipairs(p.handles or {}) do
				local hx, hy = WorkPlaneView.pixel(view, s, origin, h)
				if hx then
					love.graphics.setColor(HANDLE_COLOR)
					love.graphics.line(x, y, hx, hy)
					love.graphics.circle("fill", hx, hy, POINT_SIZE - 1)
				end
			end
			love.graphics.setColor(POINT_COLOR)
			love.graphics.rectangle("fill", x - POINT_SIZE, y - POINT_SIZE, POINT_SIZE * 2, POINT_SIZE * 2)
		end
	end
	love.graphics.pop()
end

return ShapeOverlay
