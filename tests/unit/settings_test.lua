local Settings = require("src.game.settings")
local Config = require("src.game.config")

test("settings default to the top-down view", function()
	assertEqual("topdown", Settings.default().view)
end)

test("validate keeps a known view and drops an unknown one", function()
	assertEqual("iso", Settings.validate(Config, { view = "iso" }).view)
	assertEqual("topdown", Settings.validate(Config, { view = "bogus" }).view)
	assertEqual("topdown", Settings.validate(Config, { view = 3 }).view)
	assertEqual("topdown", Settings.validate(Config, nil).view)
end)

test("views lists every configured view, top-down first", function()
	local names = Settings.views(Config)
	local n = 0
	for _ in pairs(Config.views) do
		n = n + 1
	end
	assertEqual(n, #names)
	assertEqual("topdown", names[1])
end)

test("encode and decode round trip; garbage decodes to defaults", function()
	for _, name in ipairs(Settings.views(Config)) do
		assertEqual(name, Settings.decode(Config, Settings.encode(Settings.validate(Config, { view = name }))).view)
	end
	assertEqual("topdown", Settings.decode(Config, "\0\1garbage").view)
	assertEqual("topdown", Settings.decode(Config, "view=nope\n").view)
	assertEqual("topdown", Settings.decode(Config, nil).view)
end)

local Palette = require("src.game.palette")

local function sameColor(a, b)
	return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

test("settings start on the default team colours", function()
	local s = Settings.default()
	assertTrue(sameColor(Palette.DEFAULT_PRIMARY, s.primary), "primary")
	assertTrue(sameColor(Palette.DEFAULT_SECONDARY, s.secondary), "secondary")
end)

test("the two team colours round trip exactly", function()
	local s = { view = "iso", primary = { 0.1, 1 / 3, 0.9 }, secondary = { 0, 0.25, 1 } }
	local back = Settings.decode(Config, Settings.encode(s))
	assertEqual("iso", back.view)
	assertTrue(sameColor(s.primary, back.primary), "primary")
	assertTrue(sameColor(s.secondary, back.secondary), "secondary")
end)

test("missing or bad colours fall back to the defaults", function()
	-- A settings file from before team colours: only the view.
	local old = Settings.decode(Config, "view=iso\n")
	assertEqual("iso", old.view)
	assertTrue(sameColor(Palette.DEFAULT_PRIMARY, old.primary), "old file primary")
	assertTrue(sameColor(Palette.DEFAULT_SECONDARY, old.secondary), "old file secondary")
	local bad = Settings.decode(Config, "view=iso\nprimary=0.5 2 0.1\nsecondary=red\n")
	assertTrue(sameColor(Palette.DEFAULT_PRIMARY, bad.primary), "out of range")
	assertTrue(sameColor(Palette.DEFAULT_SECONDARY, bad.secondary), "not numbers")
	local partial = Settings.validate(Config, { view = "iso", primary = { 0.5, 0.5 } })
	assertTrue(sameColor(Palette.DEFAULT_PRIMARY, partial.primary), "two channels")
end)

test("a settings record's palette derives from its two colours", function()
	local s = Settings.validate(Config, { primary = { 0.4, 0.5, 0.6 }, secondary = { 0.1, 0.2, 0.3 } })
	local p = Settings.palette(s)
	assertEqual(Palette.key(Palette.derive(s.primary, s.secondary)), Palette.key(p))
end)
