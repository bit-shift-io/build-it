-- Team colours at bake (docs/CONTEXT.md "Team palette", "Baker"): a slot
-- vertex takes the owner's palette colour, and the sprite cache key follows
-- the palette. Only the pure parts; baking itself is e2e.
local Baker = require("src.app.bake.baker")
local DesignCache = require("src.app.bake.design_cache")
local Palette = require("src.game.palette")

local RED = Palette.derive({ 1, 0, 0 }, { 0, 0, 1 })

test("a slot vertex bakes in the palette's colour, a literal one in its own", function()
	local r, g, b = Baker.color({ r = 0.1, g = 0.2, b = 0.3, slot = "primaryDark" }, RED)
	assertEqual(RED.primaryDark[1], r)
	assertEqual(RED.primaryDark[2], g)
	assertEqual(RED.primaryDark[3], b)
	r, g, b = Baker.color({ r = 0.1, g = 0.2, b = 0.3 }, RED)
	assertEqual(0.1, r)
	assertEqual(0.3, b)
	r = Baker.color({ r = 0.1, g = 0.2, b = 0.3, slot = "primary" }, nil)
	assertEqual(0.1, r, "no palette: the colour the mesh drew it in")
end)

test("the sprite key holds the palette, so a new team colour rebakes", function()
	local bp = { hash = "abc" }
	local blue = Palette.derive({ 0, 0, 1 }, { 0, 0, 1 })
	assertEqual(DesignCache.key(bp, 2, "iso", RED), DesignCache.key(bp, 2, "iso", Palette.derive({ 1, 0, 0 }, { 0, 0, 1 })))
	assertTrue(DesignCache.key(bp, 2, "iso", RED) ~= DesignCache.key(bp, 2, "iso", blue), "palette in the key")
	assertTrue(DesignCache.key(bp, 2, "topdown", RED) ~= DesignCache.key(bp, 2, "iso", RED), "view in the key")
	assertEqual("abc@x2", DesignCache.key(bp, 2, "topdown", nil), "no palette: the old key")
end)
