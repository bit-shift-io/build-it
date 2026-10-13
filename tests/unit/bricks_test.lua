local Bricks = require("src.game.builder.bricks")
local Config = require("src.game.config")

local CFG = Config.builder

test("each brick shape has its footprint, swapped by a quarter turn", function()
	local expected = {
		["1x1"] = { 1, 1 },
		["1x2"] = { 2, 1 },
		["1x4"] = { 4, 1 },
		["2x2"] = { 2, 2 },
		["2x4"] = { 4, 2 },
		slope = { 2, 2 },
	}
	for _, shape in ipairs(CFG.bricks) do
		local e = assert(expected[shape.name], "unexpected shape " .. shape.name)
		for rotation = 0, 3 do
			local w, d = Bricks.footprint(shape.name, rotation, CFG)
			local turned = rotation % 2 == 1
			assertEqual(turned and e[2] or e[1], w, shape.name .. " width at rotation " .. rotation)
			assertEqual(turned and e[1] or e[2], d, shape.name .. " depth at rotation " .. rotation)
		end
		expected[shape.name] = nil
	end
	assertEqual(nil, next(expected), "expected every shape in the palette")
end)

-- The brick's cells keyed "x,y" -> shape and dir ("box" or "slope:S").
local function cellMap(brick)
	local out, n = {}, 0
	for _, c in ipairs(Bricks.cells(brick, CFG)) do
		assertEqual(brick.z, c.z)
		out[c.x .. "," .. c.y] = c.shape == "slope" and "slope:" .. c.dir or c.shape
		n = n + 1
	end
	return out, n
end

test("a slope brick falls toward the south unturned and turns its slope row with it", function()
	local cells, n = cellMap({ x = 3, y = 5, z = 2, shape = "slope", rotation = 0 })
	assertEqual(4, n)
	assertEqual("box", cells["3,5"])
	assertEqual("box", cells["4,5"])
	assertEqual("slope:S", cells["3,6"])
	assertEqual("slope:S", cells["4,6"])

	-- A quarter turn clockwise: the south row comes round to the west.
	cells = cellMap({ x = 3, y = 5, z = 2, shape = "slope", rotation = 1 })
	assertEqual("slope:W", cells["3,5"])
	assertEqual("slope:W", cells["3,6"])
	assertEqual("box", cells["4,5"])
	assertEqual("box", cells["4,6"])

	cells = cellMap({ x = 0, y = 0, z = 2, shape = "slope", rotation = 2 })
	assertEqual("slope:N", cells["0,0"])
	assertEqual("box", cells["0,1"])
	cells = cellMap({ x = 0, y = 0, z = 2, shape = "slope", rotation = 3 })
	assertEqual("slope:E", cells["1,0"])
	assertEqual("box", cells["0,0"])
end)

test("a turned long brick covers its turned footprint", function()
	local cells, n = cellMap({ x = 1, y = 0, z = 0, shape = "2x4", rotation = 1 })
	assertEqual(8, n)
	for x = 1, 2 do
		for y = 0, 3 do
			assertEqual("box", cells[x .. "," .. y], "expected a cell at " .. x .. "," .. y)
		end
	end
end)

local Draft = require("src.game.builder.draft")

test("every shape places at every rotation, covering exactly its turned footprint", function()
	for _, shape in ipairs(CFG.bricks) do
		for rotation = 0, 3 do
			local d = Draft.new()
			Draft.resize(d, 2, 2, CFG)
			local held = { shape = shape.name, rotation = rotation, material = "stone", paint = 3 }
			local brick = Draft.place(d, 1, 1, 0, CFG, held)
			local label = shape.name .. " at rotation " .. rotation
			assertTrue(brick, "expected " .. label .. " to place")
			assertEqual(shape.name, brick.shape)
			assertEqual(rotation, brick.rotation)
			assertEqual("stone", brick.material)
			assertEqual(3, brick.paint)
			local w, dp = Bricks.footprint(shape.name, rotation, CFG)
			assertEqual(brick, Draft.brickAt(d, 1, 1, 0), label)
			assertEqual(brick, Draft.brickAt(d, w, dp, 0), label)
			assertEqual(nil, Draft.brickAt(d, 1 + w, 1, 0), label)
			assertEqual(nil, Draft.brickAt(d, 1, 1 + dp, 0), label)
		end
	end
end)

test("a long brick turned across the baseplate's edge is refused", function()
	local d = Draft.new() -- 4x4 studs
	local held = { shape = "1x4", rotation = 0, material = "plank", paint = 1 }
	assertTrue(Draft.fits(d, 0, 3, 0, CFG, held))
	held.rotation = 1
	local ok, reason = Draft.fits(d, 0, 3, 0, CFG, held)
	assertFalse(ok)
	assertEqual("outside", reason)
end)

test("the draft's model carries each brick's turned cells, paint and material", function()
	local d = Draft.new()
	Draft.place(d, 0, 0, 0, CFG, { shape = "slope", rotation = 1, material = "stone", paint = 8 })
	local m = Draft.toModel(d, CFG)
	assertEqual(4, #m.cells)
	for _, c in ipairs(m.cells) do
		assertEqual("stone", c.material)
		assertEqual(CFG.palette[8], c.color)
		if c.x == 0 then
			assertEqual("slope", c.shape)
			assertEqual("W", c.dir)
		else
			assertEqual("box", c.shape)
		end
	end
end)
