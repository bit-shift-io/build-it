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
	Fake.tap(game, "7")
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
	Fake.tap(game, "7")
	assertEqual("library", screen.tool)
	Fake.tap(game, "9")
	assertEqual("library", screen.tool)
	local slot = ScriptBuilderScreen.topBar(screen)[1]
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
