-- The Insert tool in the script builder through the real input path
-- (src/app/flow.lua): key 3 opens a menu of primitives and prefabs, role
-- prefabs included; picking one and clicking the view places it on the
-- work plane under the pointer. The properties strip edits the selected
-- primitive's dimensions and segments.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local Sandbox = require("src.game.script.sandbox")
local ScriptBuilderScreen = require("src.app.screens.script_builder")
local Insert = require("src.game.builder.insert")
local BuilderCamera = require("src.app.builder_camera")

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

local EMPTY = 'return group{ id = "root" }\n'

-- The screen pixel where design-space point p (tiles) shows.
local function pixel(screen, p)
	local s, o = screen.cfg.studsPerTile, screen.origin
	return BuilderCamera.project(ScriptBuilderScreen.view(screen), (p[1] - o[1]) * s, (p[2] - o[2]) * s, p[3] * s)
end

-- Picks `label` from the Insert menu (key 2) and clicks the ground at
-- design-space (x, y).
local function insert(game, screen, label, x, y)
	Fake.tap(game, "2")
	if label ~= "Box" and label ~= "Sphere" and label ~= "Cylinder" and label ~= "Cone" and label ~= "Wedge" then
		local menu = ScriptBuilderScreen.insertMenu(screen)
		local last = menu[#menu]
		Fake.click(game, 1, last.x + last.width / 2, last.y + last.height / 2)
		local layout = assert(ScriptBuilderScreen.libraryPanel(screen), "the picker is open")
		for _, row in ipairs(layout.rows) do
			if row.entry.name == label then
				-- Scroll the row into the list, as the wheel would.
				screen.insert.picker.scroll = layout.scroll + row.y - layout.list.y
				layout = ScriptBuilderScreen.libraryPanel(screen)
				for _, r in ipairs(layout.rows) do
					if r.entry.name == label then
						row = r
					end
				end
				Fake.click(game, 1, row.x + row.width / 2, row.y + row.height / 2)
				Fake.click(game, 1, pixel(screen, { x, y, 0 }))
				return
			end
		end
		error("no prefab " .. label)
	end
	local rows = assert(ScriptBuilderScreen.insertMenu(screen), "the insert menu is open")
	for _, row in ipairs(rows) do
		if row.item.label == label then
			Fake.click(game, 1, row.x + row.width / 2, row.y + row.height / 2)
			Fake.click(game, 1, pixel(screen, { x, y, 0 }))
			return
		end
	end
	error("no insert item " .. label)
end

local function withCtrl(game, key)
	local input = Fake.FakeInput.new()
	input:press("lctrl")
	Fake.tap(game, key)
	input:release("lctrl")
end

-- The design file `name` as saved, run.
local function saved(name)
	local text = assert(love.filesystem.read(Config.designs.dir .. "/" .. name .. ".lua"))
	return assert(Sandbox.run(text, name)).root
end

test("a box and a Saw inserted and saved make a design the picker offers, with a cost", function()
	local game, screen = openBuilder("mill", EMPTY)
	insert(game, screen, "Box", 1, 1)
	assertEqual(nil, screen.message, screen.message)
	assertEqual(1, #screen.scene.root.children)
	insert(game, screen, "saw", 1.5, 1.25)
	assertEqual(nil, screen.message, screen.message)
	withCtrl(game, "s")
	local root = saved("mill")
	assertEqual("box", root.children[1].kind)
	assertEqual(1, root.children[1].transform.move[1])
	assertEqual("saw", root.children[2].prefab)
	assertEqual(1.25, root.children[2].transform.move[2])
	Fake.tap(game, "escape")
	assertEqual("world", game.flow.screen)
	Fake.tap(game, "1")
	local found
	for _, d in ipairs(game.flow.world.picker.designs) do
		if d.name == "mill" then
			found = d
		end
	end
	assertTrue(found ~= nil, "mill is in the picker")
	assertTrue(found.blueprint.cost.plank > 0, "it has a cost")
	assertEqual("saw", found.blueprint.roles.abilities[1].ability)
end)

-- Types `text` into the properties strip's box for `key` of the selection
-- and keeps it with Return.
local function setProperty(game, screen, key, text)
	for _, f in ipairs(ScriptBuilderScreen.properties(screen)) do
		if f.prop.key == key then
			Fake.click(game, 1, f.x + f.width / 2, f.y + f.height / 2)
			for _ = 1, #screen.field.text do
				Fake.tap(game, "backspace")
			end
			Fake.typeText(game, text)
			Fake.tap(game, "return")
			return
		end
	end
	error("no property " .. key)
end

test("every primitive is placeable and editable: each inserted, its strip edited, and saved", function()
	local game, screen = openBuilder("kit", EMPTY)
	local edits = {
		{ "Box", "height", "2" },
		{ "Sphere", "segments", "8" },
		{ "Cylinder", "radius", "0.75" },
		{ "Cone", "height", "3" },
		{ "Wedge", "width", "1.5" },
	}
	for i, e in ipairs(edits) do
		insert(game, screen, e[1], i * 2, 1)
		assertEqual(nil, screen.message, screen.message)
		assertEqual(screen.scene.root.children[i].id, screen.scene.selection[1])
		setProperty(game, screen, e[2], e[3])
		assertEqual(nil, screen.message, screen.message)
	end
	assertEqual(10, #screen.history.past, "an insert and an edit are one undo step each")
	withCtrl(game, "s")
	local nodes = saved("kit").children
	assertEqual(2, nodes[1].size[3])
	assertEqual(8, nodes[2].segments)
	assertEqual(0.75, nodes[3].radius)
	assertEqual(3, nodes[4].height)
	assertEqual(1.5, nodes[5].size[1])
	assertEqual("wedge", nodes[5].kind)
end)

test("a bad value in the strip is refused with why, and digit keys typed there pick no tool", function()
	local game, screen = openBuilder("kit", EMPTY)
	insert(game, screen, "Cylinder", 1, 1)
	local f = ScriptBuilderScreen.properties(screen)[3]
	assertEqual("segments", f.prop.key)
	Fake.click(game, 1, f.x + f.width / 2, f.y + f.height / 2)
	Fake.tap(game, "backspace")
	Fake.tap(game, "backspace")
	-- LÖVE sends each digit as a key press, then as text.
	for _, digit in ipairs({ "4", "0", "0", "0" }) do
		Fake.tap(game, digit)
		Fake.typeText(game, digit)
	end
	assertEqual("select", screen.tool)
	Fake.tap(game, "return")
	assertTrue(screen.message and screen.message:find("segments", 1, true), tostring(screen.message))
	assertEqual(24, screen.scene.root.children[1].segments)
	assertEqual(1, #screen.history.past)
end)

test("an input port inserted inside the footprint snaps to its nearest edge", function()
	local game, screen = openBuilder("yard", EMPTY)
	insert(game, screen, "Box", 0, 0)
	setProperty(game, screen, "width", "4")
	setProperty(game, screen, "depth", "3")
	setProperty(game, screen, "height", "0.25")
	-- Near the west edge, well inside the 4 x 3 footprint.
	insert(game, screen, "input_port", 0.5, 1.25)
	assertEqual(nil, screen.message, screen.message)
	assertEqual(4, screen.footprint.width)
	assertEqual(1, #screen.ports)
	local port = screen.ports[1]
	assertEqual("input", port.kind)
	assertEqual("W", port.edge)
	assertEqual(0.5, port.x)
	-- Along the edge it stays where it was put: the pad's role mark is
	-- 0.125 tiles south of its corner.
	assertEqual(1.375, port.y)
end)

test("Esc puts the Insert tool away without leaving the builder; a locked script refuses it", function()
	local game, screen = openBuilder("kit", EMPTY)
	Fake.tap(game, "2")
	assertEqual("insert", screen.tool)
	Fake.tap(game, "escape")
	assertEqual("scriptBuilder", game.flow.screen)
	assertEqual("select", screen.tool)
	assertEqual(nil, ScriptBuilderScreen.insertMenu(screen))
	game, screen = openBuilder("posts", 'local n = 2\nreturn box{ size = { n, 1, 1 } }\n')
	Fake.tap(game, "2")
	assertEqual("select", screen.tool)
	assertTrue(screen.message and screen.message:find("Locked", 1, true), tostring(screen.message))
end)

test("Insert shows the Work plane section and places on the chosen plane", function()
	local game, screen = openBuilder("pad", EMPTY)
	assertEqual(nil, ScriptBuilderScreen.workPlane(screen))
	Fake.tap(game, "2")
	local layout = assert(ScriptBuilderScreen.workPlane(screen), "the section shows with Insert on")
	local function click(r)
		Fake.click(game, 1, r.x + r.width / 2, r.y + r.height / 2)
	end
	for _, b in ipairs(layout.buttons) do
		if b.plane == "XZ" then
			click(b)
		end
	end
	click(ScriptBuilderScreen.workPlane(screen).stepper.plus)
	assertEqual("XZ", screen.planeName)
	assertEqual(0.25, screen.planeHeight)
	assertEqual("insert", screen.tool)
	local row = ScriptBuilderScreen.insertMenu(screen)[1]
	click(row)
	Fake.click(game, 1, pixel(screen, { 1, 0.25, 1 }))
	local node = screen.scene.root.children[1]
	assertTrue(node ~= nil, tostring(screen.message))
	assertEqual(0.25, node.transform.move[2])
end)

test("picking Box closes the menu, stays armed, and the next view click places it; Esc places nothing", function()
	local game, screen = openBuilder("menu", EMPTY)
	Fake.tap(game, "2")
	local rows = ScriptBuilderScreen.insertMenu(screen)
	assertEqual("Prefab…", rows[#rows].item.label)
	for _, row in ipairs(rows) do
		assertTrue(row.item.prefab == nil, "no prefab names in the menu")
	end
	Fake.click(game, 1, rows[#rows].x + 5, rows[#rows].y + 5)
	assertEqual(nil, screen.insert.armed)
	assertEqual(nil, ScriptBuilderScreen.insertMenu(screen))
	Fake.tap(game, "escape")
	Fake.tap(game, "2")
	rows = ScriptBuilderScreen.insertMenu(screen)
	Fake.click(game, 1, rows[1].x + 5, rows[1].y + 5)
	assertEqual(nil, ScriptBuilderScreen.insertMenu(screen))
	assertEqual("box", screen.insert.armed.kind)
	Fake.click(game, 1, pixel(screen, { 1, 1, 0 }))
	assertEqual(1, #screen.scene.root.children)
	assertEqual("select", screen.tool)

	Fake.tap(game, "2")
	Fake.click(game, 1, ScriptBuilderScreen.insertMenu(screen)[1].x + 5, ScriptBuilderScreen.insertMenu(screen)[1].y + 5)
	Fake.tap(game, "escape")
	assertEqual("select", screen.tool)
	assertEqual(1, #screen.scene.root.children)
end)

test("Insert > Prefab... opens a picker of every prefab, role prefabs included, with no tabs or buttons", function()
	local game, screen = openBuilder("pick", EMPTY)
	Fake.tap(game, "2")
	local menu = ScriptBuilderScreen.insertMenu(screen)
	local last = menu[#menu]
	Fake.click(game, 1, last.x + 5, last.y + 5)
	assertEqual(nil, screen.libraryOpen)
	assertEqual(nil, ScriptBuilderScreen.insertMenu(screen))
	local layout = ScriptBuilderScreen.libraryPanel(screen)
	assertEqual("Pick a prefab", layout.header.text)
	assertEqual(0, #layout.tabs)
	assertEqual(nil, layout.new)
	local names = {}
	for _, row in ipairs(layout.rows) do
		names[row.entry.name] = true
		assertEqual(0, #row.buttons)
	end
	assertTrue(names.bed and names.saw and names.input_port, "bed, saw and a role prefab are listed")
end)

test("clicking the bed row arms it and closes the picker; the next view click places it, one undo removes it", function()
	local game, screen = openBuilder("bedpick", EMPTY)
	insert(game, screen, "bed", 1, 1)
	assertEqual(nil, ScriptBuilderScreen.libraryPanel(screen))
	assertEqual(1, #screen.scene.root.children)
	assertEqual("bed", screen.scene.root.children[1].prefab)
	withCtrl(game, "z")
	assertEqual(0, #screen.scene.root.children)
end)

test("Esc in the picker arms nothing and puts Insert away", function()
	local game, screen = openBuilder("pickesc", EMPTY)
	Fake.tap(game, "2")
	local menu = ScriptBuilderScreen.insertMenu(screen)
	local last = menu[#menu]
	Fake.click(game, 1, last.x + 5, last.y + 5)
	Fake.tap(game, "escape")
	assertEqual(nil, ScriptBuilderScreen.libraryPanel(screen))
	assertEqual(nil, screen.insert)
	assertEqual("select", screen.tool)
	assertEqual(0, #screen.scene.root.children)
end)
