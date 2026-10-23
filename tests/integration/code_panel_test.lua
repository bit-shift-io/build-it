-- The script builder's code panel (top bar 6) through the real input path
-- (src/app/flow.lua): the open script as text with line numbers, typing,
-- selection, copy and paste, Ctrl+Enter running it, an error marking its
-- line, and Open folder showing the save path.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local DesignStore = require("src.app.design_store")
local TextBuffer = require("src.game.text_buffer")
local Serialize = require("src.game.script.serialize")
local ScriptBuilderScreen = require("src.app.screens.script_builder")

local CFG = Config.designs

local HUT = [[return group{ id = "root", box{ id = "base", size = { 1, 1, 1 } } }]]

local function configFor(name)
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.scriptBuilder = {}
	for k, v in pairs(Config.scriptBuilder) do
		config.scriptBuilder[k] = v
	end
	config.scriptBuilder.testDesign = name .. ".lua"
	return config
end

local function builder(hut)
	_G.love = LoveMock.new()
	assert(DesignStore.write(CFG, "designs", "hut", hut or HUT))
	local game = GameHarness.startSession(World.new(20, 20), { config = configFor("hut") })
	Fake.tap(game, "b")
	return game, game.flow.scriptBuilder
end

-- The code panel's text as it stands.
local function code(screen)
	return TextBuffer.text(screen.code.buffer)
end

-- Opens the panel with the 6 key as LÖVE delivers it: keypressed, then
-- the key's own textinput, in one frame.
local function openPanel(game)
	game:keypressed("6")
	game:textinput("6")
	require("tests.support.frame_stepper").step(game, 1)
end

test("6 opens the code panel on the script's text; digits type rather than pick tools", function()
	local game, screen = builder()
	openPanel(game)
	assertTrue(ScriptBuilderScreen.codePanel(screen) ~= nil, "the panel opens")
	assertTrue(ScriptBuilderScreen.modal(screen), "Esc closes the panel, not the builder")
	local shown = Serialize.tree(screen.scene.root)
	assertEqual(shown, code(screen), "the opening key's 6 is not typed")
	Fake.tap(game, "1")
	Fake.typeText(game, "1")
	assertEqual("code", screen.tool, "1 picks no tool")
	assertEqual("1" .. shown, code(screen))
	Fake.tap(game, "escape")
	assertEqual(nil, ScriptBuilderScreen.codePanel(screen))
	assertEqual("scriptBuilder", game.flow.screen)
end)

-- Holds Ctrl for one key tap.
local function ctrl(game, key)
	local input = Fake.FakeInput.new()
	input:press("lctrl")
	Fake.tap(game, key)
	input:release("lctrl")
end

-- A design as an LLM might write it: a loop of posts round a floor.
local POSTS = [[-- Four posts on a 3x2 floor.
local height = UI.number({ default = 2, min = 1, max = 4 })
local parts = { box{ name = "Floor", size = { 3, 2, 0.25 } } }
for i = 0, 3 do
	parts[#parts + 1] = box{
		name = "Post " .. i,
		size = { 0.25, 0.25, height },
		transform = { move = { (i % 2) * 2.75, math.floor(i / 2) * 1.75, 0.25 } },
	}
end
return group(parts)
]]

test("a pasted design runs with Ctrl+Enter: it renders, locked, its params shown", function()
	local game, screen = builder()
	openPanel(game)
	love._state.clipboard = POSTS
	ctrl(game, "a")
	ctrl(game, "v")
	assertEqual(POSTS, code(screen))
	assertTrue(ScriptBuilderScreen.dirty(screen), "unrun code is an unsaved change")
	ctrl(game, "return")
	assertEqual(nil, screen.message)
	assertEqual(nil, screen.code.errorLine)
	assertTrue(screen.locked, "code locks it")
	assertEqual(3, screen.blueprint.width)
	assertEqual(2, screen.blueprint.depth)
	assertEqual("height", screen.params[1].name)
	assertTrue(ScriptBuilderScreen.codePanel(screen) ~= nil, "the panel stays up")
	ctrl(game, "s")
	assertEqual(POSTS, love.filesystem.read(CFG.dir .. "/hut.lua"), "Ctrl+S writes the code as typed")
	assertFalse(ScriptBuilderScreen.dirty(screen))
end)

test("a script that fails marks its error line and keeps the model", function()
	local game, screen = builder()
	openPanel(game)
	love._state.clipboard = "return group{\n\tbox{ size = { 1, 1, 1 } },\n\tbox{ size = nope + 1 },\n}\n"
	ctrl(game, "a")
	ctrl(game, "v")
	ctrl(game, "return")
	assertEqual(3, screen.code.errorLine)
	assertTrue(screen.message:find(":3:", 1, true), screen.message)
	assertEqual(1, screen.blueprint.width, "the last good model stays")
	-- Fixing it clears the mark.
	TextBuffer.place(screen.code.buffer, 3, 0)
	Fake.tap(game, "end")
	for _ = 1, #"{ size = nope + 1 }," do
		Fake.tap(game, "backspace")
	end
	Fake.typeText(game, "{ size = { 2, 1, 1 } },")
	ctrl(game, "return")
	assertEqual(nil, screen.code.errorLine)
	assertFalse(screen.locked, "declarative code stays editable")
	assertEqual(2, #screen.scene.root.children)
end)

local CodePanel = require("src.app.ui.code_panel")

-- The screen point of buffer position (line, col) with nothing scrolled.
local function at(layout, line, col)
	return layout.text.x + col * CodePanel.CHAR_WIDTH + 1, layout.text.y + (line - 1) * CodePanel.LINE_HEIGHT + 2
end

test("a click places the cursor, a drag selects and Ctrl+C copies it", function()
	local game, screen = builder()
	openPanel(game)
	love._state.clipboard = "alpha\nbravo\ncharlie"
	ctrl(game, "a")
	ctrl(game, "v")
	local layout = ScriptBuilderScreen.codePanel(screen)
	local x1, y1 = at(layout, 1, 2)
	local x2, y2 = at(layout, 2, 3)
	Fake.drag(game, 1, x1, y1, x2, y2)
	ctrl(game, "c")
	assertEqual("pha\nbra", love._state.clipboard)
	Fake.click(game, 1, at(layout, 3, 1))
	Fake.typeText(game, "X")
	assertEqual("alpha\nbravo\ncXharlie", code(screen))
	assertEqual(nil, screen.scene.selection[1], "clicks in the panel select no node")
end)

test("Open folder opens the save folder and shows its path", function()
	local game, screen = builder()
	openPanel(game)
	local layout = ScriptBuilderScreen.codePanel(screen)
	local folder = love.filesystem.getSaveDirectory() .. "/" .. CFG.dir
	Fake.click(game, 1, layout.folder.x + 4, layout.folder.y + 4)
	assertEqual("file://" .. folder, love._state.opened[1])
	assertTrue(screen.status:find(folder, 1, true), screen.status)
	love._state.openFails = true
	Fake.click(game, 1, layout.folder.x + 4, layout.folder.y + 4)
	assertTrue(screen.status:find(folder, 1, true), "a blocked open still shows the path")
end)

test("the wheel over the panel scrolls a long script, and typing keeps the cursor in view", function()
	local game, screen = builder()
	openPanel(game)
	local lines = {}
	for i = 1, 200 do
		lines[i] = "-- line " .. i
	end
	love._state.clipboard = table.concat(lines, "\n")
	ctrl(game, "a")
	ctrl(game, "v")
	local layout = ScriptBuilderScreen.codePanel(screen)
	assertEqual(200 - layout.rows, screen.code.scroll, "pasting at the end scrolls to it")
	game:mousemoved(layout.text.x + 10, layout.text.y + 10, 0, 0)
	game:wheelmoved(0, 2)
	assertEqual(200 - layout.rows - 6, screen.code.scroll)
	Fake.typeText(game, "x")
	assertEqual(200 - layout.rows, screen.code.scroll, "typing on the last line scrolls back to it")
	game:wheelmoved(0, -50)
	assertEqual(200 - layout.rows, screen.code.scroll, "never past the end")
end)
