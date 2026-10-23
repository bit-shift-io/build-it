-- The script builder's library manager (top bar 7) through the real input
-- path (src/app/flow.lua; docs/CONTEXT.md "Design library"): Designs and
-- Prefabs tabs of rows with Open, Duplicate, Rename and Delete (Reset for
-- a built-in), New, and the unsaved-changes prompt before the builder
-- switches script.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local DesignStore = require("src.app.design_store")
local Designs = require("tests.support.designs")
local ScriptBuilderScreen = require("src.app.screens.script_builder")

local CFG = Config.designs

local HUT = Designs.floor(1, 1)
local LAMP = [[return box{ id = "lamp", size = { 0.5, 0.5, 1 } }]]
local HOUSE = Designs.floor(2, 2, 'prefab("lamp", { id = "lamp1" })')

-- A copy of Config whose script builder opens `name`.lua.
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

-- A game in the builder on design "hut", with designs `designs` and
-- prefabs `prefabs` ({ [name] = text }) in the save directory.
local function builder(designs, prefabs)
	_G.love = LoveMock.new()
	assert(DesignStore.write(CFG, "designs", "hut", HUT))
	for name, text in pairs(designs or {}) do
		assert(DesignStore.write(CFG, "designs", name, text))
	end
	for name, text in pairs(prefabs or {}) do
		assert(DesignStore.write(CFG, "prefabs", name, text))
	end
	local game = GameHarness.startSession(World.new(20, 20), { config = configFor("hut") })
	Fake.tap(game, "b")
	assertEqual("scriptBuilder", game.flow.screen)
	return game, game.flow.scriptBuilder
end

local function clickAt(game, r)
	Fake.click(game, 1, r.x + r.width / 2, r.y + r.height / 2)
end

local function names(layout)
	local out = {}
	for i, row in ipairs(layout.rows) do
		out[i] = row.entry.name
	end
	return table.concat(out, ",")
end

local function tab(game, screen, which)
	for _, t in ipairs(ScriptBuilderScreen.libraryPanel(screen).tabs) do
		if t.tab == which then
			clickAt(game, t)
			return
		end
	end
	error("no tab " .. which)
end

-- Clicks button `action` on the row of `name` on the open tab.
local function press(game, screen, name, action)
	for _, row in ipairs(ScriptBuilderScreen.libraryPanel(screen).rows) do
		if row.entry.name == name then
			for _, button in ipairs(row.buttons) do
				if button.action == action then
					clickAt(game, button)
					return
				end
			end
			error(name .. " has no " .. action .. " button")
		end
	end
	error("no row " .. name)
end

-- The sorted, comma-joined names of the built-in designs and `extra`.
local function builtinNames(...)
	local list = { ... }
	for _, name in ipairs(require("src.game.designs.builtins").DESIGNS) do
		list[#list + 1] = name
	end
	table.sort(list)
	return table.concat(list, ",")
end

test("7 opens the library with a Designs tab and a Prefabs tab, each row with its buttons", function()
	local game, screen = builder({ barn = HUT }, { lamp = LAMP })
	Fake.tap(game, "7")
	local layout = assert(ScriptBuilderScreen.libraryPanel(screen), "the panel opens")
	assertTrue(ScriptBuilderScreen.modal(screen), "Esc closes the panel, not the builder")
	assertEqual(builtinNames("barn", "hut"), names(layout))
	local labels = {}
	for i, b in ipairs(layout.rows[1].buttons) do
		labels[i] = b.label
	end
	assertEqual("Open,Duplicate,Rename,Delete", table.concat(labels, ","))
	local builtin = {}
	for i, b in ipairs(layout.rows[3].buttons) do
		builtin[i] = b.label
	end
	assertEqual("Open,Duplicate,Rename,Reset", table.concat(builtin, ","), "a built-in offers Reset, not Delete")
	assertTrue(layout.rows[1].blueprint ~= nil, "a row has a thumbnail's blueprint")
	tab(game, screen, "prefabs")
	layout = ScriptBuilderScreen.libraryPanel(screen)
	assertTrue(names(layout):find("lamp", 1, true), names(layout))
	assertTrue(layout.rows[1].blueprint ~= nil, "a prefab row has a thumbnail too")
	Fake.tap(game, "escape")
	assertEqual(nil, ScriptBuilderScreen.libraryPanel(screen))
	assertEqual("scriptBuilder", game.flow.screen)
end)

test("Open switches to a script, Duplicate copies it, Rename moves its file", function()
	local game, screen = builder({ barn = HOUSE }, { lamp = LAMP })
	Fake.tap(game, "7")
	press(game, screen, "barn", "open")
	assertEqual("barn", screen.name)
	assertEqual("designs", screen.kind)
	assertEqual(nil, ScriptBuilderScreen.libraryPanel(screen), "opening a script puts the panel away")

	Fake.tap(game, "7")
	press(game, screen, "barn", "duplicate")
	assertEqual(HOUSE, love.filesystem.read(CFG.dir .. "/barn_copy.lua"), "the copy is written")
	assertTrue(names(ScriptBuilderScreen.libraryPanel(screen)):find("barn_copy", 1, true), "and listed")

	press(game, screen, "barn", "rename")
	assertTrue(screen.libraryRename ~= nil, "a name prompt opens")
	for _ = 1, #"barn" do
		Fake.tap(game, "backspace")
	end
	Fake.typeText(game, "stable")
	Fake.tap(game, "return")
	assertEqual(nil, screen.libraryRename)
	assertEqual(nil, love.filesystem.getInfo(CFG.dir .. "/barn.lua"), "the old file is gone")
	assertEqual(HOUSE, love.filesystem.read(CFG.dir .. "/stable.lua"))
	assertEqual("stable", screen.name, "the open script follows its new name")
	assertEqual(builtinNames("barn_copy", "hut", "stable"), names(ScriptBuilderScreen.libraryPanel(screen)))
end)

test("Delete arms on the first click and deletes on the second; a design using a deleted prefab names it", function()
	local game, screen = builder({ house = HOUSE }, { lamp = LAMP })
	Fake.tap(game, "7")
	tab(game, screen, "prefabs")
	press(game, screen, "lamp", "delete")
	assertEqual("lamp", screen.libraryOpen.armed)
	assertTrue(love.filesystem.getInfo(CFG.prefabDir .. "/lamp.lua") ~= nil, "one click deletes nothing")
	-- Any other click disarms it.
	press(game, screen, "saw", "open")
	Fake.tap(game, "7")
	tab(game, screen, "prefabs")
	press(game, screen, "lamp", "delete")
	tab(game, screen, "prefabs")
	assertEqual(nil, screen.libraryOpen.armed, "a click elsewhere disarms")
	press(game, screen, "lamp", "delete")
	press(game, screen, "lamp", "delete")
	assertEqual(nil, love.filesystem.getInfo(CFG.prefabDir .. "/lamp.lua"), "the second click deletes")
	assertFalse(names(ScriptBuilderScreen.libraryPanel(screen)):find("lamp", 1, true), "and it leaves the list")

	tab(game, screen, "designs")
	press(game, screen, "house", "open")
	assertEqual("house", screen.name)
	assertTrue(screen.message and screen.message:find('prefab "lamp"', 1, true), tostring(screen.message))
	assertTrue(screen.message:find("deleted or renamed", 1, true), screen.message)
end)

test("a built-in can't be renamed or deleted; Reset drops its saved copy", function()
	local game, screen = builder({}, { saw = LAMP })
	Fake.tap(game, "7")
	tab(game, screen, "prefabs")
	press(game, screen, "saw", "rename")
	assertEqual(nil, screen.libraryRename, "no prompt for a built-in")
	assertTrue(screen.message:find("built-in", 1, true), screen.message)
	press(game, screen, "saw", "reset")
	assertEqual(nil, love.filesystem.getInfo(CFG.prefabDir .. "/saw.lua"), "the shadow copy is gone")
	assertTrue(names(ScriptBuilderScreen.libraryPanel(screen)):find("saw", 1, true), "the built-in still shows")
	press(game, screen, "saw", "reset")
	assertTrue(screen.message:find("already the default", 1, true), screen.message)
end)

test("New starts an empty design under a free name, saved by Ctrl+S", function()
	local game, screen = builder({ untitled = HUT })
	Fake.tap(game, "7")
	clickAt(game, ScriptBuilderScreen.libraryPanel(screen).new)
	assertEqual("untitled2", screen.name)
	assertEqual("designs", screen.kind)
	assertFalse(screen.locked)
	assertEqual(0, #screen.scene.root.children, "an empty design")
	assertFalse(ScriptBuilderScreen.dirty(screen))
	local input = Fake.FakeInput.new()
	input:press("lctrl")
	Fake.tap(game, "s")
	input:release("lctrl")
	assertTrue(love.filesystem.getInfo(CFG.dir .. "/untitled2.lua") ~= nil)
end)

local ContextMenu = require("src.app.ui.context_menu")

local function row(screen, id)
	for _, r in ipairs(ScriptBuilderScreen.treeRows(screen)) do
		if r.node.id == id then
			return r
		end
	end
	error("no row for " .. id)
end

-- Right-clicks node `id`'s row and picks `item` from the context menu.
local function menu(game, screen, id, item)
	local r = row(screen, id)
	Fake.click(game, 2, r.x + r.width / 2, r.y + r.height / 2)
	for i, name in ipairs(screen.menu.items) do
		if name == item then
			local at = ContextMenu.row(screen.menu, i)
			Fake.click(game, 1, at.x + 5, at.y + 5)
			return
		end
	end
	error("no menu item " .. item)
end

-- Deletes the selected node of the open design: an unsaved change.
local function change(game, screen, id)
	menu(game, screen, id, "Delete")
	assertTrue(ScriptBuilderScreen.dirty(screen), "deleting a node is an unsaved change")
end

test("switching from unsaved changes asks first: Esc stays, D discards, S saves then switches", function()
	local game, screen = builder({ house = HOUSE }, { lamp = LAMP })
	Fake.tap(game, "7")
	press(game, screen, "house", "open")
	change(game, screen, "lamp1")

	Fake.tap(game, "7")
	press(game, screen, "hut", "open")
	assertTrue(screen.unsaved ~= nil, "a prompt asks before switching")
	assertEqual("house", screen.name)
	Fake.tap(game, "escape")
	assertEqual(nil, screen.unsaved)
	assertEqual("house", screen.name, "Esc stays on the changed design")
	assertEqual("scriptBuilder", game.flow.screen, "Esc closes the prompt, not the builder")

	Fake.tap(game, "7")
	press(game, screen, "hut", "open")
	Fake.tap(game, "d")
	assertEqual("hut", screen.name, "D switches")
	assertEqual(HOUSE, love.filesystem.read(CFG.dir .. "/house.lua"), "dropping the change")

	Fake.tap(game, "7")
	press(game, screen, "house", "open")
	change(game, screen, "lamp1")
	Fake.tap(game, "7")
	clickAt(game, ScriptBuilderScreen.libraryPanel(screen).new)
	Fake.tap(game, "s")
	assertEqual("untitled", screen.name, "S switches after saving")
	assertFalse(love.filesystem.read(CFG.dir .. "/house.lua"):find("lamp", 1, true), "the change was saved")
end)

test("Edit prefab and Reset to default ask before dropping unsaved changes", function()
	local game, screen = builder({ house = HOUSE }, { lamp = LAMP, saw = [[return group{ box{ id = "a" } }]] })
	Fake.tap(game, "7")
	press(game, screen, "house", "open")
	menu(game, screen, "lamp1", "Duplicate")
	assertTrue(ScriptBuilderScreen.dirty(screen))
	menu(game, screen, "lamp1", "Edit prefab")
	assertTrue(screen.unsaved ~= nil, "Edit prefab asks first")
	assertEqual("house", screen.name)
	Fake.tap(game, "d")
	assertEqual("lamp", screen.name)
	assertEqual("prefabs", screen.kind)

	Fake.tap(game, "7")
	tab(game, screen, "prefabs")
	press(game, screen, "saw", "open")
	change(game, screen, "a")
	menu(game, screen, screen.scene.root.id, "Reset to default")
	assertTrue(screen.unsaved ~= nil, "Reset to default asks first")
	assertTrue(love.filesystem.getInfo(CFG.prefabDir .. "/saw.lua") ~= nil, "nothing is reset yet")
	Fake.tap(game, "escape")
	assertTrue(love.filesystem.getInfo(CFG.prefabDir .. "/saw.lua") ~= nil, "Esc keeps the copy")
	menu(game, screen, screen.scene.root.id, "Reset to default")
	Fake.tap(game, "d")
	assertEqual(nil, love.filesystem.getInfo(CFG.prefabDir .. "/saw.lua"), "D resets")
	assertFalse(ScriptBuilderScreen.dirty(screen), "the built-in shows as opened")
end)
