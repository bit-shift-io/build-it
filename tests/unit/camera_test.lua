-- Camera follow/zoom are pure math (only attach/detach touch love.graphics),
-- so they run here with no `love` global.
local Camera = require("src.app.camera")

local CFG = { minZoom = 0.5, maxZoom = 2, zoomStep = 1.25 }

test("Camera.zoomBy zooms in per wheel notch and back out again", function()
	local cam = Camera.new()
	Camera.zoomBy(cam, 1, CFG)
	assertNear(1.25, cam.zoom)
	Camera.zoomBy(cam, -2, CFG)
	assertNear(0.8, cam.zoom)
end)

test("Camera.zoomBy clamps to the configured zoom range", function()
	local cam = Camera.new()
	Camera.zoomBy(cam, 50, CFG)
	assertNear(2, cam.zoom)
	Camera.zoomBy(cam, -50, CFG)
	assertNear(0.5, cam.zoom)
end)
