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

-- The footprint of shape `name` turned `rotation` quarter turns: width,
-- depth in studs.
function Bricks.footprint(name, rotation, cfg)
	local s = Bricks.shape(name, cfg)
	if rotation % 2 == 1 then
		return s.depth, s.width
	end
	return s.width, s.depth
end

-- The stud cells `brick` ({ x, y, z, shape, rotation }) covers, in draft
-- space: { x, y, z, shape = "box"|"slope", dir = <slope's dir> }.
function Bricks.cells(brick, cfg)
	local s = Bricks.shape(brick.shape, cfg)
	local cells = {}
	for x = 0, s.width - 1 do
		for y = 0, s.depth - 1 do
			local onSlope = (s.slope == "S" and y == s.depth - 1)
				or (s.slope == "N" and y == 0)
				or (s.slope == "E" and x == s.width - 1)
				or (s.slope == "W" and x == 0)
			table.insert(cells, { x = x, y = y, shape = onSlope and "slope" or "box", dir = onSlope and s.slope or nil })
		end
	end
	local width, depth = s.width, s.depth
	for _ = 1, brick.rotation % 4 do
		for _, c in ipairs(cells) do
			c.x, c.y = depth - 1 - c.y, c.x
			c.dir = c.dir and CLOCKWISE[c.dir]
		end
		width, depth = depth, width
	end
	for _, c in ipairs(cells) do
		c.x, c.y, c.z = brick.x + c.x, brick.y + c.y, brick.z
	end
	return cells
end

return Bricks
