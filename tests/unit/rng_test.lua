local Rng = require("src.core.rng")

test("Rng.new: same seed produces the same sequence", function()
	local a = Rng.new(42)
	local b = Rng.new(42)

	for _ = 1, 20 do
		assertEqual(a:next(), b:next())
	end
end)

test("Rng.new: different seeds produce different sequences", function()
	local a = Rng.new(1)
	local b = Rng.new(2)

	assertFalse(a:next() == b:next())
end)

test("Rng:next returns a value in [0, 1)", function()
	local rng = Rng.new(7)
	for _ = 1, 1000 do
		local v = rng:next()
		assertTrue(v >= 0 and v < 1, "expected value in [0, 1)")
	end
end)

test("Rng:range returns a value in [min, max)", function()
	local rng = Rng.new(99)
	for _ = 1, 200 do
		local v = rng:range(10, 20)
		assertTrue(v >= 10 and v < 20, "expected value in [10, 20)")
	end
end)

test("Rng:int returns integers in [min, max] inclusive, hitting both ends", function()
	local rng = Rng.new(3)
	local sawMin, sawMax = false, false
	for _ = 1, 500 do
		local v = rng:int(1, 4)
		assertEqual(math.floor(v), v, "expected an integer")
		assertTrue(v >= 1 and v <= 4, "expected value in [1, 4]")
		sawMin = sawMin or v == 1
		sawMax = sawMax or v == 4
	end
	assertTrue(sawMin and sawMax, "expected both ends of the range to appear")
end)
