-- Traits (docs/CONTEXT.md "Trait"): totals summed from a draft's bricks by
-- material, read from config.traits.
local Traits = require("src.game.builder.traits")
local Draft = require("src.game.builder.draft")
local Config = require("src.game.config")

local CFG = Config.builder

local function draftOf(materials)
	local d = Draft.new()
	d.width = 4
	for i, material in ipairs(materials) do
		assert(Draft.place(d, i - 1, 0, 0, CFG, { shape = "1x1", rotation = 0, material = material, paint = 1 }))
	end
	return d
end

test("an empty draft has every trait at zero", function()
	local t = Traits.of(Draft.new(), Config)
	for _, name in ipairs(Traits.NAMES) do
		assertEqual(0, t[name], name)
	end
end)

test("traits sum each brick's material traits", function()
	local plank, stone = Config.traits.plank, Config.traits.stone
	local t = Traits.of(draftOf({ "plank", "plank", "stone" }), Config)
	for _, name in ipairs(Traits.NAMES) do
		assertEqual(2 * plank[name] + stone[name], t[name], name)
	end
end)

test("a stone brick raises health and lowers productivity", function()
	local before = Traits.of(draftOf({ "plank" }), Config)
	local after = Traits.of(draftOf({ "plank", "stone" }), Config)
	assertTrue(after.health > before.health, "health rises")
	assertTrue(after.productivity < before.productivity, "productivity falls")
end)
