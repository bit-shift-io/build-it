-- Colours in the script builder through the real input path
-- (src/app/flow.lua): key 8, or Colour in the context menu, opens the
-- colour picker under its top bar slot; a swatch paints the selected nodes
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
local BuilderCamera = require("src.app.builder_camera")
local ContextMenu = require("src.app.ui.context_menu")

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
	for _, row in ipairs(ScriptBuilderScreen.treeRows(screen)) do
		if row.node.id == id then
			Fake.click(game, 1, row.x + row.width / 2, row.y + row.height / 2)
			return
		end
	end
	error("no row for " .. id)
end

-- Clicks the colour picker's swatch in section `section` ("slot",
-- "preset" or "recent") number `n`.
local function clickSwatch(game, screen, section, n)
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

test("key 8 opens the colour picker; a slot or a colour paints the selection, undoes and saves", function()
	local game, screen = openBuilder("barn", DESIGN)
	clickRow(game, screen, "wall")
	Fake.tap(game, "8")
	assertEqual("colour", screen.tool)

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

	Fake.tap(game, "escape")
	assertEqual(nil, ScriptBuilderScreen.colourPicker(screen))
	assertEqual("select", screen.tool)
end)

test("the recent row keeps the last 8 picks, newest first, and repicks from it", function()
	local game, screen = openBuilder("shed", DESIGN)
	clickRow(game, screen, "wall")
	Fake.tap(game, "8")
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
	Fake.tap(game, "escape")
	Fake.tap(game, "b")
	Fake.tap(game, "8")
	assertEqual(ColourPicker.PRESETS[2][1], clickSwatch(game, screen, "recent", 1).color[1], "kept across openings this session")
end)

test("Colour in the context menu opens the picker on the node right-clicked", function()
	local game, screen = openBuilder("hutch", DESIGN)
	clickRow(game, screen, "post")
	local s, o = screen.cfg.studsPerTile, screen.origin
	local x, y = BuilderCamera.project(ScriptBuilderScreen.view(screen), (1 - o[1]) * s, (0.5 - o[2]) * s, 1 * s)
	Fake.click(game, 2, x, y)
	local menu = assert(screen.menu, "the context menu is open")
	for i, item in ipairs(menu.items) do
		if item == "Colour" then
			local r = ContextMenu.row(menu, i)
			Fake.click(game, 1, r.x + r.width / 2, r.y + r.height / 2)
		end
	end
	assertTrue(ScriptBuilderScreen.colourPicker(screen), "the colour picker is open")
	clickSwatch(game, screen, "slot", 4)
	assertEqual("secondary", node(screen, "wall").color)
	assertEqual(nil, node(screen, "post").color)
end)
