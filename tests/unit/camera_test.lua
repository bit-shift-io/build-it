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

local Config = require("src.game.config")
local Projection = require("src.game.projection")

test("Camera.follow in the top-down view centres on the world position in pixels", function()
	local cam = Camera.new()
	local p = Projection.new(Config, 1, Config.views.topdown)
	Camera.follow(cam, p, 3, 5)
	assertNear(3 * Config.tileSize, cam.x)
	assertNear(5 * Config.tileSize, cam.y)
end)

test("Camera.follow in an iso view centres on where the view draws the position", function()
	local cam = Camera.new()
	local p = Projection.new(Config, 1, Config.views.iso2to1)
	Camera.follow(cam, p, 3, 5)
	local sx, sy = Projection.worldToScreen(p, 3, 5, 0)
	assertNear(sx, cam.x)
	assertNear(sy, cam.y)
	assertTrue(cam.x ~= 3 * Config.tileSize, "not the top-down pixel")
end)
