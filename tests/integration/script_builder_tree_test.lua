-- The script builder's tree panel, context menu, top bar and saving,
-- through the real input path (src/app/flow.lua): rows select nodes,
-- double-click renames, a right-click without movement opens the menu,
-- number keys pick tools, and Ctrl+S writes the design file.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local ScriptBuilderScreen = require("src.app.screens.script_builder")
local ContextMenu = require("src.app.ui.context_menu")
local BuilderCamera = require("src.app.builder_camera")

local HOUSE = [[
return group{ id = "root", name = "House",
	box{ id = "base", name = "Base", size = { 2, 2, 1 } },
	sphere{ id = "dome", radius = 0.5, transform = { move = { 1, 1, 1 } } },
}
]]

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

-- The middle of the tree panel row showing node `id`.
local function rowCenter(screen, id)
	for _, row in ipairs(ScriptBuilderScreen.treeRows(screen)) do
		if row.node.id == id then
			return row.x + row.width / 2, row.y + row.height / 2
		end
	end
	error("no row for " .. id)
end

local function clickRow(game, screen, id)
	local x, y = rowCenter(screen, id)
	Fake.click(game, 1, x, y)
end

test("the tree panel lists every node; a click selects one and a Ctrl-click adds another", function()
	local game, screen = openBuilder("house", HOUSE)
	assertEqual(nil, screen.message, screen.message)
	local rows = ScriptBuilderScreen.treeRows(screen)
	assertEqual(3, #rows)
	assertEqual("House", rows[1].label)
	assertEqual("dome", rows[3].label)
	clickRow(game, screen, "base")
	assertEqual("base", screen.scene.selection[1])
	local input = Fake.FakeInput.new()
	input:press("lctrl")
	clickRow(game, screen, "dome")
	input:release("lctrl")
	assertEqual(2, #screen.scene.selection)
end)

local function withCtrl(game, key)
	local input = Fake.FakeInput.new()
	input:press("lctrl")
	Fake.tap(game, key)
	input:release("lctrl")
end

local function savedFile(name)
	return love.filesystem.read(Config.designs.dir .. "/" .. name .. ".lua")
end

test("a double-click renames a row by typing, and Ctrl+S saves the name into the file", function()
	local game, screen = openBuilder("house", HOUSE)
	clickRow(game, screen, "dome")
	clickRow(game, screen, "dome")
	assertTrue(screen.rename ~= nil, "expected the rename box")
	for _ = 1, 4 do
		Fake.tap(game, "backspace")
	end
	-- Number keys type into the box rather than picking tools.
	Fake.tap(game, "5")
	Fake.typeText(game, "Roof 7")
	Fake.tap(game, "return")
	assertEqual(nil, screen.rename)
	assertEqual("select", screen.tool)
	assertEqual("Roof 7", ScriptBuilderScreen.treeRows(screen)[3].label)
	withCtrl(game, "s")
	local saved = assert(savedFile("house"), screen.status)
	assertTrue(saved:find('name = "Roof 7"', 1, true) ~= nil, saved)
	assertTrue(saved:find('id = "dome"', 1, true) ~= nil, saved)
	-- Reopening reads the saved copy.
	Fake.tap(game, "escape")
	Fake.tap(game, "b")
	assertEqual("Roof 7", ScriptBuilderScreen.treeRows(screen)[3].label)
end)

test("a right-click opens the menu on the row under it; Delete removes that node", function()
	local game, screen = openBuilder("house", HOUSE)
	local x, y = rowCenter(screen, "dome")
	Fake.click(game, 2, x, y)
	assertTrue(screen.menu ~= nil, "expected the context menu")
	assertEqual("dome", screen.scene.selection[1])
	-- Esc closes the menu, not the builder.
	Fake.tap(game, "escape")
	assertEqual(nil, screen.menu)
	assertEqual("scriptBuilder", game.flow.screen)
	Fake.click(game, 2, x, y)
	local row = ContextMenu.row(screen.menu, 2)
	assertEqual("Delete", screen.menu.items[2])
	Fake.click(game, 1, row.x + 5, row.y + 5)
	assertEqual(nil, screen.menu)
	assertEqual(2, #ScriptBuilderScreen.treeRows(screen))
end)

test("a right-drag orbits the camera without opening the menu", function()
	local game, screen = openBuilder("house", HOUSE)
	local yaw = screen.camera.yaw
	Fake.drag(game, 2, 600, 400, 700, 380)
	assertEqual(nil, screen.menu)
	assertTrue(screen.camera.yaw ~= yaw, "expected the camera to turn")
end)

test("number keys and clicks on the top bar pick tools; empty slots pick nothing", function()
	local game, screen = openBuilder("house", HOUSE)
	assertEqual("select", screen.tool)
	Fake.tap(game, "4")
	assertEqual("library", screen.tool)
	Fake.tap(game, "9")
	assertEqual("library", screen.tool)
	local slot = ScriptBuilderScreen.topBar(screen)[4]
	Fake.click(game, 1, slot.x + 2, slot.y + 2)
	assertEqual("select", screen.tool)
	assertEqual(nil, screen.libraryOpen)
end)

test("pressing the active tool's number, or clicking its slot, puts it away", function()
	local game, screen = openBuilder("house", HOUSE)
	assertEqual(4, #ScriptBuilderScreen.topBar(screen))
	Fake.tap(game, "2")
	assertEqual("insert", screen.tool)
	Fake.tap(game, "2")
	assertEqual("select", screen.tool)
	assertEqual(nil, screen.insert)
	local slot = ScriptBuilderScreen.topBar(screen)[4]
	Fake.click(game, 1, slot.x + 2, slot.y + 2)
	assertEqual("library", screen.tool)
	Fake.click(game, 1, slot.x + 2, slot.y + 2)
	assertEqual("select", screen.tool)
end)

test("clicking the model selects the node under the pointer; clicking empty space clears it", function()
	local game, screen = openBuilder("house", HOUSE)
	local studs = screen.cfg.studsPerTile
	-- The top of the dome, in blueprint space (the footprint's corner at 0, 0).
	local sx, sy = BuilderCamera.project(ScriptBuilderScreen.view(screen), 1 * studs, 1 * studs, 1.45 * studs)
	Fake.click(game, 1, sx, sy)
	assertEqual("dome", screen.scene.selection[1])
	local w, h = love.graphics.getDimensions()
	Fake.click(game, 1, w - 5, h - 5)
	assertEqual(0, #screen.scene.selection)
end)

test("Ctrl+Z undoes a delete and Ctrl+Y redoes it", function()
	local game, screen = openBuilder("house", HOUSE)
	local x, y = rowCenter(screen, "base")
	Fake.click(game, 2, x, y)
	local row = ContextMenu.row(screen.menu, 2)
	Fake.click(game, 1, row.x + 5, row.y + 5)
	assertEqual(2, #ScriptBuilderScreen.treeRows(screen))
	withCtrl(game, "z")
	assertEqual(3, #ScriptBuilderScreen.treeRows(screen))
	withCtrl(game, "y")
	assertEqual(2, #ScriptBuilderScreen.treeRows(screen))
end)

local LOOP = [[
-- Three posts in a row.
local posts = {}
for i = 1, 3 do
	posts[i] = box{ id = "post" .. i, size = { 0.25, 0.25, 2 }, transform = { move = { i - 1, 0, 0 } } }
end
return group{ id = "root", unpack(posts) }
]]

test("a hand-written loop file opens locked: edits are refused and saving keeps its code", function()
	local game, screen = openBuilder("posts", LOOP)
	assertEqual(nil, screen.message, screen.message)
	assertTrue(screen.locked, "expected a locked script")
	assertEqual(4, #ScriptBuilderScreen.treeRows(screen))
	local x, y = rowCenter(screen, "post2")
	Fake.click(game, 2, x, y)
	local row = ContextMenu.row(screen.menu, 2)
	Fake.click(game, 1, row.x + 5, row.y + 5)
	assertEqual(4, #ScriptBuilderScreen.treeRows(screen))
	assertTrue(screen.message and screen.message:find("Locked", 1, true), tostring(screen.message))
	clickRow(game, screen, "post1")
	clickRow(game, screen, "post1")
	assertEqual(nil, screen.rename)
	withCtrl(game, "s")
	assertEqual(LOOP, savedFile("posts"))
end)

local SHAPE = [[
return group{ id = "root", shape{ id = "s", points = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } } } }
]]

local function panelClick(game, screen, label)
	for _, b in ipairs(ScriptBuilderScreen.actionPanel(screen).buttons) do
		if b.label == label then
			Fake.click(game, 1, b.x + 5, b.y + 5)
			return
		end
	end
	error("no panel button " .. label)
end

test("the action panel shows the hint with nothing selected", function()
	local game, screen = openBuilder("shape", SHAPE)
	local panel = ScriptBuilderScreen.actionPanel(screen)
	assertEqual("Select something, or press 2 to draw.", panel.hint)
	assertEqual(0, #panel.buttons)
end)

test("the action panel mirrors the menu and Make 3D then Extrude works from it", function()
	local game, screen = openBuilder("shape", SHAPE)
	clickRow(game, screen, "s")
	local Actions = require("src.game.builder.actions")
	local want = Actions.of(screen.scene, screen.scene.selection, screen.lib, screen.locked)
	local got = {}
	for i, b in ipairs(ScriptBuilderScreen.actionPanel(screen).buttons) do
		got[i] = b.label
	end
	assertEqual(table.concat(want, "|"), table.concat(got, "|"))
	panelClick(game, screen, "Make 3D")
	assertEqual("◂ Back", ScriptBuilderScreen.actionPanel(screen).buttons[4].label)
	panelClick(game, screen, "Extrude")
	assertEqual("extrude", screen.scene.root.children[1].kind)
end)

test("a click on the action panel does not select through to the view", function()
	local game, screen = openBuilder("shape", SHAPE)
	clickRow(game, screen, "s")
	local p = ScriptBuilderScreen.actionPanel(screen)
	Fake.click(game, 1, p.x + p.width - 2, p.y + p.height - 1)
	assertEqual("s", screen.scene.selection[1])
end)

local function headerAt(screen, name)
	for _, s in ipairs(ScriptBuilderScreen.column(screen).sections) do
		if s.name == name then
			return s.header
		end
	end
end

local function manyBoxes(count)
	local parts = {}
	for i = 1, count do
		parts[i] = string.format('\tbox{ id = "b%d", name = "B%d", size = { 1, 1, 1 } },', i, i)
	end
	return 'return group{ id = "root", name = "Root",\n' .. table.concat(parts, "\n") .. "\n}\n"
end

test("collapsing Tree hides its rows, lifts Actions, and a click there selects nothing", function()
	local game, screen = openBuilder("house", HOUSE)
	local before = headerAt(screen, "actions").y
	local x, y = rowCenter(screen, "base")
	local header = headerAt(screen, "tree")
	Fake.click(game, 1, header.x + 5, header.y + 5)
	assertEqual(0, #ScriptBuilderScreen.treeRows(screen))
	assert(headerAt(screen, "actions").y < before, "Actions moved up")
	Fake.click(game, 1, x, y)
	assertEqual(0, #screen.scene.selection)
	Fake.click(game, 1, header.x + 5, header.y + 5)
	assertEqual(3, #ScriptBuilderScreen.treeRows(screen))
end)

test("the wheel over the column scrolls it, and a click on a scrolled row selects that node", function()
	local game, screen = openBuilder("many", manyBoxes(50))
	local zoom = screen.camera.distance
	local col = ScriptBuilderScreen.column(screen)
	assert(col.maxScroll > 0, "tree is taller than the window")
	game:mousemoved(50, 300, 0, 0)
	game:wheelmoved(0, -3)
	assertEqual(90, screen.column.scroll)
	assertEqual(zoom, screen.camera.distance)
	for _, row in ipairs(ScriptBuilderScreen.treeRows(screen)) do
		if row.y >= 200 and row.y < 220 then
			Fake.click(game, 1, row.x + 10, row.y + 10)
			assertEqual(row.node.id, screen.scene.selection[1])
			return
		end
	end
	error("no row at y 200")
end)

test("dragging the scroll bar thumb scrolls the column", function()
	local game, screen = openBuilder("many", manyBoxes(50))
	local thumb = ScriptBuilderScreen.column(screen).bar.thumb
	Fake.drag(game, 1, thumb.x + 2, thumb.y + 2, thumb.x + 2, thumb.y + 102)
	assert(screen.column.scroll > 0, "scrolled")
	assertEqual(nil, screen.column.dragging)
end)

test("collapsed sections stay collapsed when another script opens", function()
	local game, screen = openBuilder("house", HOUSE)
	local header = headerAt(screen, "tree")
	Fake.click(game, 1, header.x + 5, header.y + 5)
	assertEqual(true, screen.column.collapsed.tree)
	love.filesystem.write("other.lua", HOUSE)
	ScriptBuilderScreen.open(screen)
	assertEqual(true, screen.column.collapsed.tree)
end)
