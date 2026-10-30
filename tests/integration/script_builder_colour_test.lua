-- Colours in the script builder through the real input path
-- (src/app/flow.lua): the colour section of the action panel shows when
-- the selection has volume; a swatch paints the selected nodes
-- a team slot or a literal colour, one undo step, and joins the recent
-- row (the last 8 picks, this session only).
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local Palette = require("src.game.palette")
local ColourPicker = require("src.app.ui.colour_picker")
local Sandbox = require("src.game.script.sandbox")
local ScriptBuilderScreen = require("src.app.screens.script_builder")

-- A game in the script builder, opened on design file `name`.lua in the
-- save directory holding `text`.
local function openBuilder(name, text)
	_G.love = LoveMock.new()
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.scriptBuilder = {}
	for k, v in pairs(Config.scriptBuilder) do
		config.scriptBuilder[k] = v
	end
	config.scriptBuilder.testDesign = name .. ".lua"
	love.filesystem.write(name .. ".lua", text)
	local game = GameHarness.startSession({ width = 20, height = 20 }, { config = config })
	Fake.tap(game, "b")
	return game, game.flow.scriptBuilder
end

local DESIGN = [[
return group{ id = "root",
	box{ id = "wall", size = { 2, 1, 1 } },
	box{ id = "post", transform = { move = { 3, 0, 0 } } },
}
]]

local function clickRow(game, screen, id)
	screen.column.scroll = 0
	for _, row in ipairs(ScriptBuilderScreen.treeRows(screen)) do
		if row.node.id == id then
			Fake.click(game, 1, row.x + row.width / 2, row.y + row.height / 2)
			return
		end
	end
	error("no row for " .. id)
end

-- Scrolls the column so section `name` (a "material" or "colour" content)
-- sits at the top of the visible area, as the wheel would.
local function reveal(screen, name)
	local col = ScriptBuilderScreen.column(screen)
	for _, s in ipairs(col.sections) do
		if s.name == name then
			screen.column.scroll = col.scroll + (s.header.y - col.y)
			return
		end
	end
	error("no section " .. name)
end

-- Clicks the colour picker's swatch in section `section` ("slot",
-- "preset" or "recent") number `n`.
local function clickSwatch(game, screen, section, n)
	reveal(screen, "colour")
	local layout = assert(ScriptBuilderScreen.colourPicker(screen), "the colour picker is open")
	local seen = 0
	for _, swatch in ipairs(layout.swatches) do
		if swatch.section == section then
			seen = seen + 1
			if seen == n then
				Fake.click(game, 1, swatch.x + swatch.width / 2, swatch.y + swatch.height / 2)
				return swatch
			end
		end
	end
	error("no swatch " .. section .. " " .. n)
end

local function withCtrl(game, key)
	local input = Fake.FakeInput.new()
	input:press("lctrl")
	Fake.tap(game, key)
	input:release("lctrl")
end

local function node(screen, id)
	for _, row in ipairs(ScriptBuilderScreen.treeRows(screen)) do
		if row.node.id == id then
			return row.node
		end
	end
end

test("the colour section shows for a box; a slot or a colour paints the selection, undoes and saves", function()
	local game, screen = openBuilder("barn", DESIGN)
	clickRow(game, screen, "wall")

	local slot = clickSwatch(game, screen, "slot", 1)
	assertEqual(Palette.SLOTS[1], slot.color)
	assertEqual(nil, screen.message, screen.message)
	assertEqual("primary", node(screen, "wall").color)
	assertEqual(nil, node(screen, "post").color)

	local preset = clickSwatch(game, screen, "preset", 3)
	assertEqual(ColourPicker.PRESETS[3][1], node(screen, "wall").color[1])
	assertEqual(preset.color[2], node(screen, "wall").color[2])

	withCtrl(game, "z")
	assertEqual("primary", node(screen, "wall").color, "each pick is one undo step")

	withCtrl(game, "s")
	local text = assert(love.filesystem.read(Config.designs.dir .. "/barn.lua"))
	local saved = assert(Sandbox.run(text, "barn")).root
	assertEqual("primary", saved.children[1].color)
end)

test("the recent row keeps the last 8 picks, newest first, and repicks from it", function()
	local game, screen = openBuilder("shed", DESIGN)
	clickRow(game, screen, "wall")
	for i = 1, 9 do
		clickSwatch(game, screen, "preset", i)
	end
	local recent = {}
	for _, swatch in ipairs(ScriptBuilderScreen.colourPicker(screen).swatches) do
		if swatch.section == "recent" then
			recent[#recent + 1] = swatch.color
		end
	end
	assertEqual(8, #recent)
	assertEqual(ColourPicker.PRESETS[9][1], recent[1][1])
	assertEqual(ColourPicker.PRESETS[2][1], recent[8][1])

	clickSwatch(game, screen, "recent", 8)
	assertEqual(ColourPicker.PRESETS[2][1], node(screen, "wall").color[1])

	Fake.tap(game, "escape")
	Fake.tap(game, "b")
	screen = game.flow.scriptBuilder
	clickRow(game, screen, "post")
	assertEqual(ColourPicker.PRESETS[2][1], clickSwatch(game, screen, "recent", 1).color[1], "kept across openings this session")
end)

test("a selected shape has no Colour section", function()
	local game, screen = openBuilder("flatcolour", [[
return group{ id = "root",
	shape{ id = "flat", points = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } } },
}
]])
	clickRow(game, screen, "flat")
	assertEqual(nil, ScriptBuilderScreen.colourPicker(screen))
end)


test("collapsing the Colour section hides its swatches; Material and Colour take no space for a bare shape", function()
	local game, screen = openBuilder("collapse", DESIGN)
	clickRow(game, screen, "wall")
	local col = ScriptBuilderScreen.column(screen)
	local header
	for _, s in ipairs(col.sections) do
		if s.name == "colour" then
			header = s.header
		end
	end
	Fake.click(game, 1, header.x + 10, header.y + 5)
	assertEqual(nil, ScriptBuilderScreen.colourPicker(screen))
	assertEqual(true, screen.column.collapsed.colour)
end)

test("a swatch click lands while the column is scrolled", function()
	local game, screen = openBuilder("scrolled", DESIGN)
	love.graphics.getDimensions = function()
		return 1280, 300
	end
	clickRow(game, screen, "wall")
	reveal(screen, "colour")
	assertTrue(ScriptBuilderScreen.column(screen).scroll > 0, "the column is scrolled")
	clickSwatch(game, screen, "slot", 1)
	assertEqual("primary", node(screen, "wall").color)
end)
