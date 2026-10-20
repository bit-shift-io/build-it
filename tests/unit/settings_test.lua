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
		assertEqual(name, Settings.decode(Config, Settings.encode({ view = name })).view)
	end
	assertEqual("topdown", Settings.decode(Config, "\0\1garbage").view)
	assertEqual("topdown", Settings.decode(Config, "view=nope\n").view)
	assertEqual("topdown", Settings.decode(Config, nil).view)
end)
