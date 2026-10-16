-- The built-in starting storage facility (docs/CONTEXT.md "Storage
-- facility"): a design defined in code, placed free at the world centre in
-- a new game (Session.newGame). It keeps the look of the old hard-coded
-- test house -- walls, a gable roof, a door and windows on the south face,
-- a chimney -- rebuilt from real bricks, with a depot, storage bricks and
-- an input and an output port on the south face. Pure -- no `love.*`.
--
-- Its id is reserved, outside the library's "dN" scheme
-- (docs/memory/design-id-reuse.md), so it never collides with a library
-- design or its DesignCache key.
local Draft = require("src.game.builder.draft")

local Starter = {}

Starter.ID = "starter-storage"

-- Paints (config.builder.palette indexes).
local WALL, DOOR, WINDOW, ROOF, CHIMNEY = 4, 10, 7, 1, 12

local WIDTH, DEPTH = 3, 2 -- tiles
local WALL_HEIGHT = 6 -- layers

-- The wall paint of stud (x, y, z) on the wall ring of a w x d stud
-- baseplate: the door and windows on the south face, two windows east.
local function wallPaint(x, y, z, w, d)
	if y == d - 1 and (x == 2 or x == 3) and z <= 2 then
		return DOOR
	end
	if z == 2 or z == 3 then
		if y == d - 1 and (x == 6 or x == 7 or x == 9 or x == 10) then
			return WINDOW
		end
		if x == w - 1 and (y == 3 or y == 4) then
			return WINDOW
		end
	end
	return WALL
end

local RUNS = { { 4, "1x4" }, { 2, "1x2" }, { 1, "1x1" } }

-- Lays the free studs of one wall line in bricks: `cells` lists the line's
-- studs { x, y } in order; `rotation` turns 1xN bricks along it (0 east,
-- 1 south). Consecutive studs of one paint share a brick, longest first.
local function wallLine(draft, cells, z, rotation, cfg, w, d)
	local i = 1
	while i <= #cells do
		local c = cells[i]
		if Draft.brickAt(draft, c.x, c.y, z) then
			i = i + 1
		else
			local paint = wallPaint(c.x, c.y, z, w, d)
			local n = 1
			while cells[i + n] and not Draft.brickAt(draft, cells[i + n].x, cells[i + n].y, z) and wallPaint(cells[i + n].x, cells[i + n].y, z, w, d) == paint do
				n = n + 1
			end
			for _, run in ipairs(RUNS) do
				if n >= run[1] then
					n = run[1]
					assert(Draft.place(draft, c.x, c.y, z, cfg, { shape = run[2], rotation = rotation, material = "plank", paint = paint }))
					break
				end
			end
			i = i + n
		end
	end
end

local function line(x0, y0, dx, dy, n)
	local cells = {}
	for k = 0, n - 1 do
		cells[#cells + 1] = { x = x0 + k * dx, y = y0 + k * dy }
	end
	return cells
end

local function put(draft, shape, x, y, z, cfg, rotation, material, paint)
	assert(Draft.place(draft, x, y, z, cfg, { shape = shape, rotation = rotation or 0, material = material or "plank", paint = paint or WALL }))
end

-- The starter version: a WIDTH x DEPTH tile draft. cfg is config.builder.
local function version(cfg)
	local studs = cfg.studsPerTile
	local w, d = WIDTH * studs, DEPTH * studs
	local draft = Draft.new()
	assert(Draft.resize(draft, WIDTH, DEPTH, cfg))

	-- Inside: the depot and the storage bricks along the north wall.
	put(draft, "depot", 1, 1, 0, cfg)
	for x = 3, w - 3, 2 do
		put(draft, "storage", x, 1, 0, cfg)
	end
	for x = 1, w - 3, 2 do
		put(draft, "storage", x, 3, 0, cfg)
	end
	-- Ports at ground level in the south wall, facing south.
	put(draft, "input", 6, d - 1, 0, cfg)
	put(draft, "output", 9, d - 1, 0, cfg)

	for z = 0, WALL_HEIGHT - 1 do
		wallLine(draft, line(0, 0, 1, 0, w), z, 0, cfg, w, d)
		wallLine(draft, line(0, d - 1, 1, 0, w), z, 0, cfg, w, d)
		wallLine(draft, line(0, 1, 0, 1, d - 2), z, 1, cfg, w, d)
		wallLine(draft, line(w - 1, 1, 0, 1, d - 2), z, 1, cfg, w, d)
	end

	-- Gable roof: each layer steps in one row from the north and south
	-- eaves, filled between; a flat ridge on top.
	local layers = d / 2 - 1
	for layer = 0, layers - 1 do
		local z = WALL_HEIGHT + layer
		for x = 0, w - 2, 2 do
			put(draft, "slope", x, layer, z, cfg, 2, "plank", ROOF)
			put(draft, "slope", x, d - 2 - layer, z, cfg, 0, "plank", ROOF)
			for y = layer + 2, d - 4 - layer, 2 do
				put(draft, "2x2", x, y, z, cfg, 0, "plank", WALL)
			end
		end
	end
	for x = 0, w - 4, 4 do
		put(draft, "2x4", x, layers, WALL_HEIGHT + layers, cfg, 0, "plank", ROOF)
	end
	-- The chimney, east of the ridge's middle.
	for z = WALL_HEIGHT + layers + 1, WALL_HEIGHT + layers + 2 do
		put(draft, "2x2", w - 4, layers, z, cfg, 0, "stone", CHIMNEY)
	end
	return draft
end

-- The starter design: { id = Starter.ID, name, versions = { <version> } }.
function Starter.design(config)
	return { id = Starter.ID, name = "Storage", versions = { version(config.builder) } }
end

return Starter
