local Palette = require("src.game.palette")

local function assertColor(expected, actual, message)
	for i = 1, 3 do
		assertNear(expected[i], actual[i], 1e-9, message)
	end
end

test("a palette derives every slot from primary and secondary", function()
	local p = Palette.derive({ 0.5, 0.2, 0.1 }, { 0.1, 0.3, 0.6 })
	assertEqual(7, #Palette.SLOTS)
	for _, slot in ipairs(Palette.SLOTS) do
		assertEqual(3, #p[slot], slot)
	end
	assertColor({ 0.5, 0.2, 0.1 }, p.primary)
	assertColor({ 0.1, 0.3, 0.6 }, p.secondary)
	-- Dark shades are darker and light ones lighter, in every channel.
	for _, base in ipairs({ "primary", "secondary" }) do
		for i = 1, 3 do
			assertTrue(p[base .. "Dark"][i] < p[base][i], base .. "Dark")
			assertTrue(p[base .. "Light"][i] > p[base][i], base .. "Light")
		end
	end
	for i = 1, 3 do
		assertTrue(p.highlight[i] > p.primaryLight[i], "highlight lighter than primaryLight")
	end
end)

test("a palette's key follows its colours", function()
	local a = Palette.derive({ 0.5, 0.2, 0.1 }, { 0.1, 0.3, 0.6 })
	local same = Palette.derive({ 0.5, 0.2, 0.1 }, { 0.1, 0.3, 0.6 })
	local other = Palette.derive({ 0.5, 0.2, 0.2 }, { 0.1, 0.3, 0.6 })
	assertEqual(Palette.key(a), Palette.key(same))
	assertTrue(Palette.key(a) ~= Palette.key(other), "a new primary gives a new key")
	assertTrue(Palette.key(a) ~= Palette.key(Palette.derive({ 0.5, 0.2, 0.1 }, { 0.1, 0.3, 0.7 })), "secondary too")
	assertTrue(Palette.key(a):match("^[%w]+$") ~= nil, "plain text, safe in a cache key")
end)

test("slot names are known; anything else isn't", function()
	assertTrue(Palette.isSlot("primary"))
	assertTrue(Palette.isSlot("highlight"))
	assertFalse(Palette.isSlot("purple"))
	assertFalse(Palette.isSlot(nil))
end)
