-- The builder's orbit camera: a perspective view circling the model. Pure
-- math, no `love.*`, so the ray it builds for picking and the projection
-- the live view draws with (src/app/render/script_builder_view.lua) are the
-- same transform and unit-testable.
--
-- Space is studs (config.builder.studsPerTile to a tile), x east, y south,
-- z up. cfg is config.builder; cfg.camera holds the orbit tuning.
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

-- Turns the camera by a drag of (dx, dy) pixels: sideways spins it about
-- the model, down tilts it to look more steeply down.
function BuilderCamera.orbit(cam, dx, dy, cfg)
	local c = cfg.camera
	cam.yaw = cam.yaw + dx * c.orbitSpeed
	cam.pitch = math.max(c.minPitch, math.min(c.maxPitch, cam.pitch + dy * c.orbitSpeed))
end

-- Zooms by `notches` wheel steps (positive zooms in), for a model held by
-- a sphere of `radius`: between radius + cfg.camera.nearMargin and
-- cfg.camera.maxDistance.
function BuilderCamera.zoomAround(cam, notches, radius, cfg)
	local c = cfg.camera
	local distance = cam.distance / c.zoomStep ^ notches
	cam.distance = math.max(radius + c.nearMargin, math.min(c.maxDistance, distance))
end

-- A frozen view for one frame, circling point `t` ({ x, y, z }) and
-- keeping outside a sphere of `radius` about it: eye position, basis,
-- focal length and the viewport (in screen pixels) it draws into. Yaw 0
-- looks north from the south; positive pitch looks down.
function BuilderCamera.viewAround(cam, t, radius, cfg, viewport)
	local c = cfg.camera
	local distance = math.max(radius + c.nearMargin, math.min(c.maxDistance, cam.distance))
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
		far = distance + radius + 1,
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
