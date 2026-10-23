-- Prefabs in the script builder through the real input path
-- (src/app/flow.lua; docs/CONTEXT.md "Prefab", "Role prefab"): Edit prefab
-- on an instance opens its prefab, a built-in as a shadow copy in the save
-- directory; every design using it changes, placed buildings don't, and
-- Reset to default restores the built-in. Export as prefab turns a
-- selection into one instance; an instance's params are overrides; Unlink
-- makes an editable copy.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local DesignStore = require("src.app.design_store")
local Designs = require("tests.support.designs")
local Sandbox = require("src.game.script.sandbox")
local ScriptBuilderScreen = require("src.app.screens.script_builder")
local ContextMenu = require("src.app.ui.context_menu")

local TILE = Config.tileSize

local BED = 'prefab("bed", { id = "bed", transform = { move = { 0.5, 0.5, 0.0625 } } })'
-- Two designs using the bed: the inn gets placed, the house gets edited.
local INN = Designs.floor(2, 2, BED, Designs.port("output", 1.625, 2))
local HOUSE = Designs.floor(1, 1, BED)

local function write(name, text)
	assert(DesignStore.write(Config.designs, "designs", name, text))
end

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

-- Leaves the builder (if in it) and opens it on design `name`.
local function openBuilder(game, name)
	if game.flow.screen == "scriptBuilder" then
		Fake.tap(game, "escape")
	end
	game.flow.scriptBuilder.scfg.testDesign = name .. ".lua"
	Fake.tap(game, "b")
	assertEqual("scriptBuilder", game.flow.screen)
	return game.flow.scriptBuilder
end

local function row(screen, id)
	for _, r in ipairs(ScriptBuilderScreen.treeRows(screen)) do
		if r.node.id == id then
			return r
		end
	end
	error("no row for " .. id)
end

local function clickRow(game, screen, id)
	local r = row(screen, id)
	Fake.click(game, 1, r.x + r.width / 2, r.y + r.height / 2)
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

local function withCtrl(game, key)
	local input = Fake.FakeInput.new()
	input:press("lctrl")
	Fake.tap(game, key)
	input:release("lctrl")
end

-- Types `text` into the properties strip's box for `key` and keeps it.
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

local function height(screen)
	return screen.bounds.maxZ
end

test("editing the bed prefab changes every design using it, not the placed inn; Reset to default restores it", function()
	_G.love = LoveMock.new()
	write("inn", INN)
	write("house", HOUSE)
	local game = GameHarness.startSession(World.new(20, 20), { storage = Config.stockpile, config = configFor("house") })
	local c = game.ctx.pools.characters[1]
	Fake.pickDesign(game, "inn")
	Fake.click(game, 1, 640 + (13 * TILE - c.x), 360 + (10 * TILE - c.y))
	GameHarness.completeSites(game)
	local inn = assert(game.ctx.pools.buildings[2], "the inn was placed")
	local placed = inn.blueprint.hash

	local screen = openBuilder(game, "inn")
	assertEqual(nil, screen.message, screen.message)
	local innHeight = height(screen)
	screen = openBuilder(game, "house")
	menu(game, screen, "bed", "Edit prefab")
	assertEqual("prefabs", screen.kind)
	assertEqual("bed", screen.name)
	assertFalse(screen.locked, "the bed is declarative")
	clickRow(game, screen, "frame")
	setProperty(game, screen, "height", "1")
	assertEqual(nil, screen.message, screen.message)
	withCtrl(game, "s")
	local shadow = assert(love.filesystem.read(Config.designs.prefabDir .. "/bed.lua"), "a shadow copy in the save directory")
	assertEqual(1, assert(Sandbox.run(shadow, "bed")).root.children[1].size[3])

	screen = openBuilder(game, "inn")
	assertNear(0.0625 + 1, height(screen), 1e-6, "the inn shows the taller bed: floor and frame")
	assertEqual(placed, game.ctx.pools.buildings[2].blueprint.hash, "the placed inn keeps its blueprint")

	screen = openBuilder(game, "house")
	menu(game, screen, "bed", "Edit prefab")
	menu(game, screen, "frame", "Reset to default")
	assertEqual(nil, love.filesystem.read(Config.designs.prefabDir .. "/bed.lua"), "the shadow is gone")
	assertEqual("prefabs", screen.kind)
	assertEqual(0.25, screen.scene.root.children[1].size[3], "the builder shows the built-in again")
	screen = openBuilder(game, "inn")
	assertNear(innHeight, height(screen), 1e-6)
end)

local YARD = [[
return group{ id = "root",
	box{ id = "a", size = { 1, 1, 1 } },
	box{ id = "b", size = { 1, 1, 2 }, transform = { move = { 2, 0, 0 } } },
	box{ id = "c" },
}
]]

-- A game in the builder on design `name` holding `text`, with prefab
-- files `prefabs` ({ [name] = text }, optional) in the save directory.
local function builderOn(name, text, prefabs)
	_G.love = LoveMock.new()
	write(name, text)
	for prefab, script in pairs(prefabs or {}) do
		assert(DesignStore.write(Config.designs, "prefabs", prefab, script))
	end
	local game = GameHarness.startSession(World.new(20, 20), { config = configFor(name) })
	return game, openBuilder(game, name)
end

test("Export as prefab writes the named prefab and turns the selection into one instance, children read-only", function()
	local game, screen = builderOn("yard", YARD)
	local bounds = screen.bounds
	clickRow(game, screen, "a")
	local input = Fake.FakeInput.new()
	input:press("lctrl")
	clickRow(game, screen, "b")
	input:release("lctrl")
	menu(game, screen, "b", "Export as prefab")
	assertTrue(screen.exportPrompt ~= nil, "a name prompt opens")
	assertTrue(ScriptBuilderScreen.modal(screen))
	Fake.typeText(game, "pair")
	Fake.tap(game, "return")
	assertEqual(nil, screen.exportPrompt)
	assertEqual(nil, screen.message, screen.message)
	local text = assert(love.filesystem.read(Config.designs.prefabDir .. "/pair.lua"), "the prefab file is written")
	assertEqual(2, #assert(Sandbox.run(text, "pair")).root.children)
	local root = screen.scene.root
	assertEqual(2, #root.children)
	assertEqual("pair", root.children[1].prefab)
	assertEqual(root.children[1].id, screen.scene.selection[1])
	assertEqual(bounds.maxX, screen.bounds.maxX, "the model looks the same")
	assertEqual(bounds.maxZ, screen.bounds.maxZ)
	local inside = row(screen, "a")
	assertTrue(inside.readOnly, "the instance's children show read-only")
	-- A click on a read-only row selects the instance it belongs to.
	clickRow(game, screen, "c")
	clickRow(game, screen, "pair1")
	local clicked = screen.clock
	Fake.runUntil(game, function()
		return screen.clock - clicked > 0.5
	end, 60)
	clickRow(game, screen, "a")
	assertEqual(nil, screen.rename)
	assertEqual("pair1", screen.scene.selection[1])
	withCtrl(game, "z")
	assertEqual(3, #screen.scene.root.children, "export undoes")
end)

test("Export refuses a name already taken and a locked script; Unlink makes an editable copy, not of a role prefab", function()
	local game, screen = builderOn("yard", YARD)
	clickRow(game, screen, "a")
	menu(game, screen, "a", "Export as prefab")
	Fake.typeText(game, "bed")
	Fake.tap(game, "return")
	assertTrue(screen.message and screen.message:find("already", 1, true), screen.message)
	assertEqual("box", screen.scene.root.children[1].kind)
	menu(game, screen, "a", "Export as prefab")
	Fake.typeText(game, "solo")
	Fake.tap(game, "return")
	assertEqual("solo", screen.scene.root.children[1].prefab)
	local id = screen.scene.root.children[1].id
	menu(game, screen, id, "Unlink")
	assertEqual(nil, screen.message, screen.message)
	local copy = screen.scene.root.children[1]
	assertEqual("group", copy.kind)
	assertFalse(row(screen, "a").readOnly, "the copy's nodes are the design's")

	write("inn_role", Designs.floor(1, 1, BED))
	screen = openBuilder(game, "inn_role")
	menu(game, screen, "bed", "Unlink")
	assertTrue(screen.message and screen.message:find("role prefab", 1, true), screen.message)
	assertEqual("prefab", screen.scene.root.children[2].kind)

	write("coded", 'local n = UI.number({ default = 1 })\nreturn group{ id = "root", box{ id = "a" } }\n')
	screen = openBuilder(game, "coded")
	assertTrue(screen.locked)
	menu(game, screen, "a", "Export as prefab")
	assertEqual(nil, screen.exportPrompt, "no prompt on a locked script")
	assertTrue(screen.message and screen.message:find("Locked", 1, true), screen.message)
end)

local POST = 'local height = UI.number({ default = 1, step = 0.5, min = 0.5 })\n'
	.. 'return group{ id = "post", box{ id = "pole", size = { 0.25, 0.25, height } } }\n'

-- The params panel row labelled `label`.
local function paramRow(screen, label)
	for _, r in ipairs(ScriptBuilderScreen.paramsPanel(screen)) do
		if r.param.label == label then
			return r
		end
	end
	error("no param row " .. label)
end

test("a selected instance's params show as inputs that override them, one undo step each, saved with the design", function()
	local game, screen = builderOn("fence", 'return group{ id = "root", prefab("post", { id = "p" }) }\n', { post = POST })
	assertEqual(nil, screen.message, screen.message)
	assertEqual(0, #ScriptBuilderScreen.paramsPanel(screen), "no params with nothing selected")
	clickRow(game, screen, "p")
	local r = paramRow(screen, "height")
	assertEqual(1, r.param.value)
	Fake.click(game, 1, r.plus.x + 2, r.plus.y + 2)
	assertEqual(nil, screen.message, screen.message)
	assertEqual(1.5, screen.scene.root.children[1].params.height)
	assertEqual(1.5, paramRow(screen, "height").param.value)
	assertNear(1.5, screen.bounds.maxZ, 1e-6)
	withCtrl(game, "s")
	local saved = assert(love.filesystem.read(Config.designs.dir .. "/fence.lua"))
	assertEqual(1.5, assert(Sandbox.run(saved, "fence")).root.children[1].params.height)
	assertEqual(POST, love.filesystem.read(Config.designs.prefabDir .. "/post.lua"), "the prefab is untouched")
	withCtrl(game, "z")
	assertNear(1, screen.bounds.maxZ, 1e-6)
end)
