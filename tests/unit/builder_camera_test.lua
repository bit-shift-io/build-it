-- The builder's orbit camera is pure math (src/app/builder_camera.lua), so
-- it runs here with no `love` global.
local BuilderCamera = require("src.app.builder_camera")
local Config = require("src.game.config")

local CFG = Config.builder
local VIEWPORT = { x = 200, y = 0, width = 1080, height = 720 }

test("the ray through a point's projected pixel passes through that point", function()
	local cam = BuilderCamera.new(CFG)
	local view = BuilderCamera.viewAround(cam, { 2, 2, 1 }, 4, CFG, VIEWPORT)
	local px, py, pz = 3, 1, 2
	local sx, sy = BuilderCamera.project(view, px, py, pz)
	local o, d = BuilderCamera.ray(view, sx, sy)

	-- Walk the ray to the point's depth along it and compare.
	local t = ((px - o[1]) * d[1] + (py - o[2]) * d[2] + (pz - o[3]) * d[3]) / (d[1] ^ 2 + d[2] ^ 2 + d[3] ^ 2)
	assertNear(px, o[1] + d[1] * t, 1e-6)
	assertNear(py, o[2] + d[2] * t, 1e-6)
	assertNear(pz, o[3] + d[3] * t, 1e-6)
end)

test("dragging orbits the camera, and pitch stays between its limits", function()
	local cam = BuilderCamera.new(CFG)
	local yaw = cam.yaw
	BuilderCamera.orbit(cam, 100, 0, CFG)
	assertNear(yaw + 100 * CFG.camera.orbitSpeed, cam.yaw)
	BuilderCamera.orbit(cam, 0, 100000, CFG)
	assertNear(CFG.camera.maxPitch, cam.pitch)
	BuilderCamera.orbit(cam, 0, -100000, CFG)
	assertNear(CFG.camera.minPitch, cam.pitch)
end)

test("the wheel zooms in and out within the camera's distance range", function()
	local cam = BuilderCamera.new(CFG)
	local start = cam.distance
	BuilderCamera.zoomAround(cam, 1, 4, CFG)
	assertTrue(cam.distance < start, "expected zooming in to bring the camera nearer")
	BuilderCamera.zoomAround(cam, -1000, 4, CFG)
	assertNear(CFG.camera.maxDistance, cam.distance)
end)

-- Fails unless every corner of a box w x d x h studs from the origin lies
-- inside the clip depth range at every yaw and at both pitch limits, the
-- camera circling the box's middle outside its bounding sphere.
local function assertNeverClips(cam, w, d, h)
	local hw, hd, hh = w / 2, d / 2, h / 2
	local radius = math.sqrt(hw * hw + hd * hd + hh * hh)
	for step = 0, 15 do
		cam.yaw = step * math.pi / 8
		for _, pitch in ipairs({ CFG.camera.minPitch, CFG.camera.maxPitch }) do
			cam.pitch = pitch
			local view = BuilderCamera.viewAround(cam, { hw, hd, hh }, radius, CFG, VIEWPORT)
			for _, x in ipairs({ 0, w }) do
				for _, y in ipairs({ 0, d }) do
					for _, z in ipairs({ 0, h }) do
						local _, _, ndcZ = BuilderCamera.project(view, x, y, z)
						assertTrue(ndcZ > -1 and ndcZ < 1, string.format("corner clipped at depth %.3f", ndcZ))
					end
				end
			end
		end
	end
end

test("zoomed fully in or out at any orbit, no part of the model clips", function()
	for _, size in ipairs({ { 4, 4, 2 }, { 16, 16, 12 } }) do
		local cam = BuilderCamera.new(CFG)
		cam.distance = 0
		assertNeverClips(cam, size[1], size[2], size[3])
		cam.distance = 1e9
		assertNeverClips(cam, size[1], size[2], size[3])
	end
end)

test("a view around a point centres it and keeps the camera outside the radius", function()
	local cam = BuilderCamera.new(CFG)
	cam.distance = 0
	local view = BuilderCamera.viewAround(cam, { 10, 4, 2 }, 6, CFG, VIEWPORT)
	local sx, sy, _, depth = BuilderCamera.project(view, 10, 4, 2)
	assertNear(VIEWPORT.x + VIEWPORT.width / 2, sx, 1e-6)
	assertNear(VIEWPORT.height / 2, sy, 1e-6)
	assertNear(6 + CFG.camera.nearMargin, depth, 1e-6)
end)

test("zooming around a radius stops at its nearest distance", function()
	local cam = BuilderCamera.new(CFG)
	BuilderCamera.zoomAround(cam, 1000, 6, CFG)
	assertNear(6 + CFG.camera.nearMargin, cam.distance, 1e-6)
end)
