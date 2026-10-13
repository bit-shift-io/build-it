-- The one 3/4 top-down projection (docs/adr/0001-2d-world-baked-block-sprites.md).
-- World rendering and the baker both go through here, so the camera and the
-- baked sprites can never diverge. Pure -- no `love.*`.
--
-- An oblique parallel projection seen from the south and above: the ground
-- plane maps 1:1 onto the screen (tiles stay square), and height lifts a
-- point straight up the screen by heightScale per unit.
--   world (x east, y south, z up), in tiles  ->  screen (x right, y down), in px
local Projection = {}

-- bakeScale (an integer, default 1) multiplies the base pixels per tile,
-- config.tileSize. World rendering uses scale 1; the baker bakes at higher
-- integer scales for zoomed-in views.
function Projection.new(config, bakeScale)
	return {
		pixelsPerTile = config.tileSize * (bakeScale or 1),
		heightScale = config.projection.heightScale,
	}
end

function Projection.worldToScreen(p, x, y, z)
	return x * p.pixelsPerTile, (y - p.heightScale * z) * p.pixelsPerTile
end

-- The world point at height z (default 0) that draws at screen (sx, sy).
function Projection.screenToWorld(p, sx, sy, z)
	return sx / p.pixelsPerTile, sy / p.pixelsPerTile + p.heightScale * (z or 0)
end

-- Distance toward the viewer, in tiles along the view ray (larger is
-- nearer). Points on one screen pixel differ by (0, heightScale, 1) along
-- the ray, so any depth rising along it orders them; this one is affine, so
-- it interpolates exactly across a triangle.
function Projection.depth(p, _x, y, z)
	return p.heightScale * y + z
end

-- Snaps to whole pixels, ignoring float noise just past an integer.
local EPSILON = 1e-9

-- The sprite a model with these bounds (in tiles, model-local) bakes into:
--   { width, height, anchorX, anchorY, pixelsPerTile }
-- The anchor is the whole-pixel point the model origin (the footprint's
-- north-west ground corner) lands on; it may lie outside the sprite.
function Projection.spriteFrame(p, bounds)
	local left = math.floor(bounds.minX * p.pixelsPerTile + EPSILON)
	local right = math.ceil(bounds.maxX * p.pixelsPerTile - EPSILON)
	local _, top = Projection.worldToScreen(p, 0, bounds.minY, bounds.maxZ)
	local _, bottom = Projection.worldToScreen(p, 0, bounds.maxY, bounds.minZ)
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
