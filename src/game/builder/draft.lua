-- A design draft (docs/CONTEXT.md "Design"): the baseplate size and the
-- bricks on it, as the builder edits them. Pure -- no `love.*`.
--
--   { width = 1, depth = 1, bricks = { <brick>, ... } }
--
-- width/depth are the baseplate in tiles. Brick space is the block model's
-- (x east, y south, z up) in studs, with z counting brick layers one stud
-- tall; the baseplate's north-west top corner is the origin.
--   brick = { x, y, z, width, depth, -- studs; occupies x .. x+width-1
--             shape, rotation, material, paint }
-- shape names one of cfg.bricks, rotation counts quarter turns clockwise
-- (src/game/builder/bricks.lua), width/depth are the turned footprint, and
-- paint indexes cfg.palette. A held brick is the same minus the position:
--   held = { shape, rotation, material, paint } -- defaults to cfg.held
-- cfg is config.builder.
local Model = require("src.game.blocks.model")
local Bricks = require("src.game.builder.bricks")

local Draft = {}

function Draft.new()
	return { width = 1, depth = 1, bricks = {} }
end

local function occupies(brick, x, y, z)
	return z == brick.z and x >= brick.x and x < brick.x + brick.width and y >= brick.y and y < brick.y + brick.depth
end

-- The brick occupying stud cell (x, y, z), or nil.
function Draft.brickAt(draft, x, y, z)
	for _, b in ipairs(draft.bricks) do
		if occupies(b, x, y, z) then
			return b
		end
	end
	return nil
end

local function overlaps(a, b)
	return a.z == b.z
		and a.x < b.x + b.width
		and b.x < a.x + a.width
		and a.y < b.y + b.depth
		and b.y < a.y + a.depth
end

-- Whether `brick` lies on a width x depth tile baseplate, at or above it.
local function onBaseplate(brick, width, depth, cfg)
	local studs = cfg.studsPerTile
	return brick.x >= 0
		and brick.y >= 0
		and brick.z >= 0
		and brick.x + brick.width <= width * studs
		and brick.y + brick.depth <= depth * studs
end

local function newBrick(x, y, z, cfg, held)
	held = held or cfg.held
	local width, depth = Bricks.footprint(held.shape, held.rotation, cfg)
	return {
		x = x,
		y = y,
		z = z,
		width = width,
		depth = depth,
		shape = held.shape,
		rotation = held.rotation,
		material = held.material,
		paint = held.paint,
	}
end

local function check(draft, brick, cfg)
	if not onBaseplate(brick, draft.width, draft.depth, cfg) then
		return false, "outside"
	end
	if brick.z >= cfg.maxLayers then
		return false, "too high"
	end
	for _, other in ipairs(draft.bricks) do
		if overlaps(brick, other) then
			return false, "overlap"
		end
	end
	return true
end

-- Whether Draft.place would take the held brick at (x, y, z): true, or
-- false and the reason it would give.
function Draft.fits(draft, x, y, z, cfg, held)
	return check(draft, newBrick(x, y, z, cfg, held), cfg)
end

-- Places a copy of the held brick with its turned footprint's north-west
-- bottom cell at (x, y, z). Returns the brick, or nil and why: "outside"
-- the baseplate, "too high" for cfg.maxLayers, or "overlap" with another
-- brick.
function Draft.place(draft, x, y, z, cfg, held)
	local brick = newBrick(x, y, z, cfg, held)
	local ok, reason = check(draft, brick, cfg)
	if not ok then
		return nil, reason
	end
	table.insert(draft.bricks, brick)
	return brick
end

-- Resizes the baseplate to width x depth tiles. Returns true, or false and
-- why: the "size" is outside cfg.minBaseplate..cfg.maxBaseplate, or
-- "bricks" would sit outside the new baseplate.
function Draft.resize(draft, width, depth, cfg)
	local min, max = cfg.minBaseplate, cfg.maxBaseplate
	if width < min or width > max or depth < min or depth > max then
		return false, "size"
	end
	for _, b in ipairs(draft.bricks) do
		if not onBaseplate(b, width, depth, cfg) then
			return false, "bricks"
		end
	end
	draft.width, draft.depth = width, depth
	return true
end

-- The draft as a block model on the stud grid: one cell per stud a brick
-- covers (Bricks.cells), in the brick's paint and material.
function Draft.toModel(draft, cfg)
	local m = Model.new(cfg.studsPerTile, draft.width, draft.depth)
	for _, b in ipairs(draft.bricks) do
		local color = cfg.palette[b.paint]
		for _, c in ipairs(Bricks.cells(b, cfg)) do
			c.color, c.material = color, b.material
			Model.addCell(m, c)
		end
	end
	return m
end

-- Takes `brick` off the draft. Bricks resting on it stay where they are.
-- True when the brick was on the draft.
function Draft.remove(draft, brick)
	for i, b in ipairs(draft.bricks) do
		if b == brick then
			table.remove(draft.bricks, i)
			return true
		end
	end
	return false
end

-- Paints `brick` with cfg.palette[paint]. True when its colour changed.
function Draft.paint(_, brick, paint)
	if brick.paint == paint then
		return false
	end
	brick.paint = paint
	return true
end

return Draft
