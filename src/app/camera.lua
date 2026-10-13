-- World camera: a centre point and a zoom. Follow and zoom are pure math;
-- only attach/detach touch love.graphics.
local Camera = {}

function Camera.new(x, y)
	return { x = x or 0, y = y or 0, zoom = 1 }
end

-- Centres the camera on a world position.
function Camera.follow(camera, x, y)
	camera.x = x
	camera.y = y
end

-- Zooms by `notches` wheel steps (positive zooms in), clamped to
-- [cfg.minZoom, cfg.maxZoom]. cfg is config.camera.
function Camera.zoomBy(camera, notches, cfg)
	local zoom = camera.zoom * cfg.zoomStep ^ notches
	camera.zoom = math.max(cfg.minZoom, math.min(cfg.maxZoom, zoom))
end

-- Pushes a transform that maps world space onto a view of the given size,
-- with the camera centre in the middle of the view. Pair with detach.
function Camera.attach(camera, viewWidth, viewHeight)
	love.graphics.push()
	love.graphics.translate(viewWidth / 2, viewHeight / 2)
	love.graphics.scale(camera.zoom)
	love.graphics.translate(-camera.x, -camera.y)
end

function Camera.detach()
	love.graphics.pop()
end

return Camera
