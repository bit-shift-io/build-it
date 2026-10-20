-- The one projection, per view (docs/adr/0001-2d-world-baked-block-sprites.md,
-- docs/adr/0005-views-are-data-baked-per-view.md).
-- World rendering and the baker both go through here, so the camera and the
-- baked sprites can never diverge. Pure -- no `love.*`.
--
-- An oblique parallel projection seen from the south and above: the ground
-- plane maps 1:1 onto the screen (tiles stay square), and height lifts a
-- point straight up the screen by heightScale per unit.
--   world (x east, y south, z up), in tiles  ->  screen (x right, y down), in px
local Projection = {}

-- A view (config.views, plain data) is { ground = { a, b, c, d }, lift,
-- depth = { x, y } }; see config.lua. In tiles:
--   screen x = a*x + b*y,  screen y = c*x + d*y - lift*z
--   depth    = depth.x*x + depth.y*y + z
-- With no view, the 3/4 top-down view built from config.projection.heightScale.
--
-- bakeScale (an integer, default 1) multiplies the base pixels per tile,
-- config.tileSize. World rendering uses scale 1; the baker bakes at higher
-- integer scales for zoomed-in views.
function Projection.new(config, bakeScale, view)
	view = view
		or {
			ground = { 1, 0, 0, 1 },
			lift = config.projection.heightScale,
			depth = { 0, config.projection.heightScale },
		}
	local a, b, c, d = view.ground[1], view.ground[2], view.ground[3], view.ground[4]
	return {
		pixelsPerTile = config.tileSize * (bakeScale or 1),
		heightScale = view.lift,
		view = view,
		a = a,
		b = b,
		c = c,
		d = d,
		det = a * d - b * c,
		depthX = view.depth[1],
		depthY = view.depth[2],
	}
end

function Projection.worldToScreen(p, x, y, z)
	return (p.a * x + p.b * y) * p.pixelsPerTile, (p.c * x + p.d * y - p.heightScale * z) * p.pixelsPerTile
end

-- The world point at height z (default 0) that draws at screen (sx, sy).
function Projection.screenToWorld(p, sx, sy, z)
	local u = sx / p.pixelsPerTile
	local v = sy / p.pixelsPerTile + p.heightScale * (z or 0)
	return (p.d * u - p.b * v) / p.det, (p.a * v - p.c * u) / p.det
end

-- Distance toward the viewer, in tiles along the view ray (larger is
-- nearer). Points on one screen pixel differ by (depth.x, depth.y, 1) along
-- the ray, so any depth rising along it orders them; this one is affine, so
-- it interpolates exactly across a triangle.
function Projection.depth(p, x, y, z)
	return p.depthX * x + p.depthY * y + z
end

-- Snaps to whole pixels, ignoring float noise just past an integer.
local EPSILON = 1e-9

-- The sprite a model with these bounds (in tiles, model-local) bakes into,
-- covering all 8 box corners (an iso box is rotated):
--   { width, height, anchorX, anchorY, pixelsPerTile }
-- The anchor is the whole-pixel point the model origin (the footprint's
-- north-west ground corner) lands on; it may lie outside the sprite.
function Projection.spriteFrame(p, bounds)
	local left, right, top, bottom = math.huge, -math.huge, math.huge, -math.huge
	for _, x in ipairs({ bounds.minX, bounds.maxX }) do
		for _, y in ipairs({ bounds.minY, bounds.maxY }) do
			for _, z in ipairs({ bounds.minZ, bounds.maxZ }) do
				local sx, sy = Projection.worldToScreen(p, x, y, z)
				left, right = math.min(left, sx), math.max(right, sx)
				top, bottom = math.min(top, sy), math.max(bottom, sy)
			end
		end
	end
	left = math.floor(left + EPSILON)
	right = math.ceil(right - EPSILON)
	top = math.floor(top + EPSILON)
	bottom = math.ceil(bottom - EPSILON)
	return {
		width = right - left,
		height = bottom - top,
		anchorX = -left,
		anchorY = -top,
		pixelsPerTile = p.pixelsPerTile,
	}
end

-- A model-local point (tiles) to its sprite pixel position.
function Projection.modelToSprite(p, frame, x, y, z)
	local sx, sy = Projection.worldToScreen(p, x, y, z)
	return sx + frame.anchorX, sy + frame.anchorY
end

-- The model-local point at height z that bakes onto sprite pixel (px, py).
function Projection.spriteToModel(p, frame, px, py, z)
	return Projection.screenToWorld(p, px - frame.anchorX, py - frame.anchorY, z)
end

-- Where a sprite baked into `frame` draws so its model origin sits on world
-- tile (tileX, tileY): its top-left in world-projection pixels, and the scale
-- to draw it at.
function Projection.placeSprite(p, frame, tileX, tileY)
	local drawScale = p.pixelsPerTile / frame.pixelsPerTile
	local sx, sy = Projection.worldToScreen(p, tileX, tileY, 0)
	return sx - frame.anchorX * drawScale, sy - frame.anchorY * drawScale, drawScale
end

-- Sprites bake at a whole multiple of the base pixels per tile, never below
-- the camera zoom: drawn sprites only ever shrink, so they never blur from
-- magnification. Exact at whole zooms, where they draw 1:1.
local ZOOM_EPSILON = 1e-6

function Projection.bakeScale(zoom)
	return math.max(1, math.ceil(zoom - ZOOM_EPSILON))
end

return Projection
