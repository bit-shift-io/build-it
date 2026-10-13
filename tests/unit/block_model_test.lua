local Model = require("src.game.blocks.model")

test("Model.bounds spans every added cell, max exclusive, in cells", function()
	local m = Model.new(4, 2, 1)
	Model.addCell(m, { x = 1, y = 0, z = 0, color = { 1, 0, 0 } })
	Model.addCell(m, { x = 5, y = 3, z = 2, shape = "slope", dir = "S", color = { 0, 1, 0 }, material = "plank" })

	local b = Model.bounds(m)
	assertEqual(1, b.minX)
	assertEqual(0, b.minY)
	assertEqual(0, b.minZ)
	assertEqual(6, b.maxX)
	assertEqual(4, b.maxY)
	assertEqual(3, b.maxZ)
end)

-- A 2x1-tile footprint at 4 cells per tile: 8 cells east-west, 4 north-south.
-- Facing E turns the model a quarter clockwise seen from above, so the
-- north-west corner cell lands on the north-east corner.
local function cornerModel()
	local m = Model.new(4, 2, 1)
	Model.addCell(m, { x = 0, y = 0, z = 0, color = { 1, 0, 0 } })
	Model.addCell(m, { x = 7, y = 3, z = 2, shape = "slope", dir = "S", color = { 0, 1, 0 }, material = "stone" })
	return m
end

test("Model.rotate to facing N leaves cells and footprint as authored", function()
	local r = Model.rotate(cornerModel(), "N")
	assertEqual(2, r.width)
	assertEqual(1, r.depth)
	assertEqual(0, r.cells[1].x)
	assertEqual(0, r.cells[1].y)
	assertEqual(7, r.cells[2].x)
	assertEqual("S", r.cells[2].dir)
end)

test("Model.rotate to facing E turns cells, slope dirs and footprint a quarter clockwise", function()
	local src = cornerModel()
	local r = Model.rotate(src, "E")
	assertEqual(1, r.width)
	assertEqual(2, r.depth)
	assertEqual(4, r.cellsPerTile)
	-- NW corner -> NE corner of the 4x8 rotated footprint.
	assertEqual(3, r.cells[1].x)
	assertEqual(0, r.cells[1].y)
	assertEqual(0, r.cells[1].z)
	-- SE corner -> SW corner; a south-looking slope now looks west.
	assertEqual(0, r.cells[2].x)
	assertEqual(7, r.cells[2].y)
	assertEqual(2, r.cells[2].z)
	assertEqual("W", r.cells[2].dir)
	assertEqual("slope", r.cells[2].shape)
	assertEqual("stone", r.cells[2].material)
	-- The source model is untouched.
	assertEqual(0, src.cells[1].x)
	assertEqual("S", src.cells[2].dir)
end)

test("Model.rotate to facing S and W keeps the footprint and maps the corner cell", function()
	local s = Model.rotate(cornerModel(), "S")
	assertEqual(2, s.width)
	assertEqual(1, s.depth)
	assertEqual(7, s.cells[1].x)
	assertEqual(3, s.cells[1].y)
	assertEqual("N", s.cells[2].dir)

	local w = Model.rotate(cornerModel(), "W")
	assertEqual(1, w.width)
	assertEqual(2, w.depth)
	assertEqual(0, w.cells[1].x)
	assertEqual(7, w.cells[1].y)
	assertEqual("E", w.cells[2].dir)
end)
