-- The builder's orbit camera: a perspective view circling the baseplate.
-- Pure math, no `love.*`, so the ray it builds for picking
-- (src/game/builder/pick.lua) and the projection the live view draws with
-- (src/app/render/builder_view.lua) are the same transform and unit-testable.
--
-- Space is draft space: studs, x east, y south, z up in brick layers.
-- cfg is config.builder; cfg.camera holds the orbit tuning.
local BuilderCamera = {}

-- Clip planes, in studs along the view direction. The camera never comes
-- nearer than nearMargin to the model's bounding sphere, so NEAR only has
-- to be smaller than that.
local NEAR = 0.5

function BuilderCamera.new(cfg)
	local c = cfg.camera
	return { yaw = c.yaw, pitch = c.pitch, distance = c.distance }
end

local function normalize(v)
	local len = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
	return { v[1] / len, v[2] / len, v[3] / len }
end

local function cross(a, b)
	return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end

local function dot(a, b)
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

-- How high the model reaches, in layers: the top of its highest brick, plus
-- one layer for a brick about to be placed on it.
local function modelTop(draft)
	local top = 0
	for _, b in ipairs(draft.bricks) do
		top = math.max(top, b.z + 1)
	end
	return top + 1
end

-- The point the camera circles: the middle of the model's box.
local function target(draft, cfg)
	local studs = cfg.studsPerTile
	return { draft.width * studs / 2, draft.depth * studs / 2, modelTop(draft) / 2 }
end

-- The radius of a sphere about the target that holds the baseplate slab
-- and every brick, including one about to be placed on top.
local function modelRadius(draft, cfg)
	local studs = cfg.studsPerTile
	local hw, hd, hh = draft.width * studs / 2, draft.depth * studs / 2, modelTop(draft) / 2 + 0.5
	return math.sqrt(hw * hw + hd * hd + hh * hh)
end

-- The nearest the camera may come to the target for this draft.
function BuilderCamera.minDistance(draft, cfg)
	return modelRadius(draft, cfg) + cfg.camera.nearMargin
end

-- Turns the camera by a drag of (dx, dy) pixels: sideways spins it about
-- the model, down tilts it to look more steeply down.
function BuilderCamera.orbit(cam, dx, dy, cfg)
	local c = cfg.camera
	cam.yaw = cam.yaw + dx * c.orbitSpeed
	cam.pitch = math.max(c.minPitch, math.min(c.maxPitch, cam.pitch + dy * c.orbitSpeed))
end

-- Zooms by `notches` wheel steps (positive zooms in), between the draft's
-- minDistance and cfg.camera.maxDistance.
function BuilderCamera.zoomBy(cam, notches, draft, cfg)
	local c = cfg.camera
	local distance = cam.distance / c.zoomStep ^ notches
	cam.distance = math.max(BuilderCamera.minDistance(draft, cfg), math.min(c.maxDistance, distance))
end

-- A frozen view for one frame: eye position, basis, focal length and the
-- viewport (in screen pixels) it draws into. Yaw 0 looks north from the
-- south; positive pitch looks down.
function BuilderCamera.view(cam, draft, cfg, viewport)
	local c = cfg.camera
	local distance = math.max(BuilderCamera.minDistance(draft, cfg), math.min(c.maxDistance, cam.distance))
	local t = target(draft, cfg)
	local cp = math.cos(cam.pitch)
	local eye = {
		t[1] + distance * cp * math.sin(cam.yaw),
		t[2] + distance * cp * math.cos(cam.yaw),
		t[3] + distance * math.sin(cam.pitch),
	}
	local forward = normalize({ t[1] - eye[1], t[2] - eye[2], t[3] - eye[3] })
	local right = normalize(cross({ 0, 0, 1 }, forward))
	local up = cross(forward, right)
	return {
		eye = eye,
		forward = forward,
		right = right,
		up = up,
		focal = (viewport.height / 2) / math.tan(c.fov / 2),
		centerX = viewport.x + viewport.width / 2,
		centerY = viewport.y + viewport.height / 2,
		near = NEAR,
		far = distance + modelRadius(draft, cfg) + 1,
	}
end

-- The point's screen pixel, its depth in GL clip range [-1, 1] (smaller is
-- nearer; docs/memory/love-12-depth-canvas.md), and its distance along the
-- view direction. Only meaningful for points in front of the near plane.
function BuilderCamera.project(view, x, y, z)
	local v = { x - view.eye[1], y - view.eye[2], z - view.eye[3] }
	local depth = dot(v, view.forward)
	local sx = view.centerX + dot(v, view.right) / depth * view.focal
	local sy = view.centerY - dot(v, view.up) / depth * view.focal
	local n, f = view.near, view.far
	local ndcZ = (f + n) / (f - n) - 2 * f * n / ((f - n) * depth)
	return sx, sy, ndcZ, depth
end

-- The ray from the eye through screen pixel (sx, sy): origin, direction.
function BuilderCamera.ray(view, sx, sy)
	local rx, uy = (sx - view.centerX) / view.focal, -(sy - view.centerY) / view.focal
	local f, r, u = view.forward, view.right, view.up
	return { view.eye[1], view.eye[2], view.eye[3] },
		{ f[1] + r[1] * rx + u[1] * uy, f[2] + r[2] * rx + u[2] * uy, f[3] + r[3] * rx + u[3] * uy }
end

return BuilderCamera
