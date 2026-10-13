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

test("Rng.hash derives a stable 32-bit seed from its parts, decorrelating near inputs", function()
	local a, b = Rng.hash("tree", 1), Rng.hash("tree", 2)
	assertEqual(a, Rng.hash("tree", 1), "expected the same parts to hash the same")
	assertTrue(a ~= b, "expected different parts to hash differently")
	assertTrue(a >= 0 and a < 4294967296 and math.floor(a) == a, "expected a 32-bit integer")
	assertTrue(Rng.hash("tree", 12) ~= Rng.hash("tree1", 2), "expected part boundaries to matter")
	-- Neighbouring seeds' first draws land far apart, not a hair apart.
	local first1, first2 = Rng.new(a):next(), Rng.new(b):next()
	assertTrue(math.abs(first1 - first2) > 0.01, "expected decorrelated first draws")
end)
