-- The brick palette (docs/CONTEXT.md "Brick"): the shapes in
-- config.builder.bricks, turned in quarter steps. Pure -- no `love.*`.
--
-- rotation counts quarter turns clockwise seen from above, 0..3, the same
-- turn as Model.rotate: (x, y) -> (depth - 1 - y, x) within the footprint.
-- cfg is config.builder.
local Bricks = {}

local CLOCKWISE = { N = "E", E = "S", S = "W", W = "N" }

-- The shape named `name` in cfg.bricks.
function Bricks.shape(name, cfg)
	for _, shape in ipairs(cfg.bricks) do
		if shape.name == name then
			return shape
		end
	end
	error("unknown brick shape " .. tostring(name))
end

-- How many layers tall shape `name` stands: one per entry of its
-- `layers`, or 1.
function Bricks.height(name, cfg)
	local s = Bricks.shape(name, cfg)
	return s.layers and #s.layers or 1
end

-- The role fields a brick of shape `name` carries (docs/CONTEXT.md
-- "Function brick", "Port", "Storage brick"): ability, port, storage.
Bricks.ROLES = { "ability", "port", "storage" }

-- The footprint edge ("N"|"S"|"W"|"E") `brick` touches at ground level
-- (z = 0) on `version`'s baseplate (a draft or saved version), or nil when
-- it is above ground or touches no edge. A brick in a corner touches two
-- edges; the north or south one wins, whatever the brick's rotation. Where
-- a port faces (src/game/buildings/placement.lua) and whether it may stand
-- there (src/game/builder/validate.lua) both come from here.
function Bricks.edge(brick, version, cfg)
	if brick.z ~= 0 then
		return nil
	end
	local studs = cfg.studsPerTile
	if brick.y == 0 then
		return "N"
	elseif brick.y + brick.depth == version.depth * studs then
		return "S"
	elseif brick.x == 0 then
		return "W"
	elseif brick.x + brick.width == version.width * studs then
		return "E"
	end
	return nil
end

-- The footprint of shape `name` turned `rotation` quarter turns: width,
-- depth in studs.
function Bricks.footprint(name, rotation, cfg)
	local s = Bricks.shape(name, cfg)
	if rotation % 2 == 1 then
		return s.depth, s.width
	end
	return s.width, s.depth
end

-- The unturned cells of a shape without `layers`: one layer of boxes, its
-- `slope` row sloped.
local function plainCells(s)
	local cells = {}
	for x = 0, s.width - 1 do
		for y = 0, s.depth - 1 do
			local onSlope = (s.slope == "S" and y == s.depth - 1)
				or (s.slope == "N" and y == 0)
				or (s.slope == "E" and x == s.width - 1)
				or (s.slope == "W" and x == 0)
			table.insert(cells, { x = x, y = y, z = 0, shape = onSlope and "slope" or "box", dir = onSlope and s.slope or nil })
		end
	end
	return cells
end

-- The unturned cells a shape's `layers` draw (config.builder.bricks).
local function layeredCells(s)
	local cells = {}
	for z, layer in ipairs(s.layers) do
		for y, row in ipairs(layer) do
			for x = 1, #row do
				local ch = row:sub(x, x)
				if ch ~= "." then
					local dir = ch:upper():match("^[NESW]$")
					table.insert(cells, {
						x = x - 1,
						y = y - 1,
						z = z - 1,
						shape = dir and "slope" or "box",
						dir = dir,
						accent = ch == "o" or ch:match("^[nesw]$") ~= nil or nil,
					})
				end
			end
		end
	end
	return cells
end

-- The stud cells `brick` ({ x, y, z, shape, rotation }) covers, in draft
-- space: { x, y, z, shape = "box"|"slope", dir = <slope's dir>, accent }.
-- accent is true on studs drawn in the shape's `accent` colour.
function Bricks.cells(brick, cfg)
	local s = Bricks.shape(brick.shape, cfg)
	local cells = s.layers and layeredCells(s) or plainCells(s)
	local width, depth = s.width, s.depth
	for _ = 1, brick.rotation % 4 do
		for _, c in ipairs(cells) do
			c.x, c.y = depth - 1 - c.y, c.x
			c.dir = c.dir and CLOCKWISE[c.dir]
		end
		width, depth = depth, width
	end
	for _, c in ipairs(cells) do
		c.x, c.y, c.z = brick.x + c.x, brick.y + c.y, brick.z + c.z
	end
	return cells
end

return Bricks
