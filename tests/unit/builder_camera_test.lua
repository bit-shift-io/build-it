-- The builder's orbit camera is pure math (src/app/builder_camera.lua), so
-- it runs here with no `love` global.
local BuilderCamera = require("src.app.builder_camera")
local Draft = require("src.game.builder.draft")
local Config = require("src.game.config")

local CFG = Config.builder
local VIEWPORT = { x = 200, y = 0, width = 1080, height = 720 }

test("the ray through a point's projected pixel passes through that point", function()
	local cam = BuilderCamera.new(CFG)
	local view = BuilderCamera.view(cam, Draft.new(), CFG, VIEWPORT)
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
	local d = Draft.new()
	local cam = BuilderCamera.new(CFG)
	local start = cam.distance
	BuilderCamera.zoomBy(cam, 1, d, CFG)
	assertTrue(cam.distance < start, "expected zooming in to bring the camera nearer")
	BuilderCamera.zoomBy(cam, -1000, d, CFG)
	assertNear(CFG.camera.maxDistance, cam.distance)
	BuilderCamera.zoomBy(cam, 1000, d, CFG)
	assertNear(BuilderCamera.minDistance(d, CFG), cam.distance)
end)

-- Every corner of the draft's box: the baseplate slab up to one layer above
-- its highest brick, where the next brick could go.
local function modelCorners(draft)
	local h = 1
	for _, b in ipairs(draft.bricks) do
		h = math.max(h, b.z + 2)
	end
	local w, d = draft.width * CFG.studsPerTile, draft.depth * CFG.studsPerTile
	local corners = {}
	for _, x in ipairs({ 0, w }) do
		for _, y in ipairs({ 0, d }) do
			for _, z in ipairs({ -0.5, h }) do
				table.insert(corners, { x, y, z })
			end
		end
	end
	return corners
end

-- Fails unless every model corner lies inside the clip depth range at
-- every yaw and at both pitch limits.
local function assertNeverClips(cam, d)
	for step = 0, 15 do
		cam.yaw = step * math.pi / 8
		for _, pitch in ipairs({ CFG.camera.minPitch, CFG.camera.maxPitch }) do
			cam.pitch = pitch
			local view = BuilderCamera.view(cam, d, CFG, VIEWPORT)
			for _, c in ipairs(modelCorners(d)) do
				local _, _, ndcZ = BuilderCamera.project(view, c[1], c[2], c[3])
				assertTrue(ndcZ > -1 and ndcZ < 1, string.format("corner clipped at depth %.3f", ndcZ))
			end
		end
	end
end

local function draftOf(size)
	local d = Draft.new()
	Draft.resize(d, size, size, CFG)
	return d
end

test("zoomed fully in or out at any orbit, no part of the model clips", function()
	for _, size in ipairs({ 1, 4 }) do
		local d = draftOf(size)
		local cam = BuilderCamera.new(CFG)
		BuilderCamera.zoomBy(cam, 1000, d, CFG)
		assertNeverClips(cam, d)
		BuilderCamera.zoomBy(cam, -1000, d, CFG)
		assertNeverClips(cam, d)
	end
end)

test("growing the baseplate while zoomed in still never clips the model", function()
	local d = draftOf(1)
	local cam = BuilderCamera.new(CFG)
	BuilderCamera.zoomBy(cam, 1000, d, CFG)
	Draft.resize(d, 4, 4, CFG)
	assertNeverClips(cam, d)
end)

test("stacking higher while zoomed in still never clips the model", function()
	local d = draftOf(1)
	local cam = BuilderCamera.new(CFG)
	BuilderCamera.zoomBy(cam, 1000, d, CFG)
	for z = 0, CFG.maxLayers - 1 do
		Draft.place(d, 0, 0, z, CFG)
	end
	assertNeverClips(cam, d)
end)

test("the camera circles the model's middle, so a short model fills the view's centre", function()
	local d = draftOf(1)
	Draft.place(d, 1, 1, 0, CFG)
	local view = BuilderCamera.view(BuilderCamera.new(CFG), d, CFG, VIEWPORT)
	local _, sy = BuilderCamera.project(view, 2, 2, 0.5)
	assertNear(VIEWPORT.y + VIEWPORT.height / 2, sy, VIEWPORT.height / 10)
end)
