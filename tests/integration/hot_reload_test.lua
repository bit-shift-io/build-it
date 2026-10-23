-- Hot reload (docs/CONTEXT.md "Design script"): a design or prefab file
-- changed on disk by an external editor reloads in the script builder
-- within a second, through the real input path (src/app/flow.lua). A clean
-- declarative file stays editable; one holding code opens locked.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local DesignStore = require("src.app.design_store")

local CFG = Config.designs

local HUT = [[return group{ id = "root", box{ id = "base", name = "Base", size = { 1, 1, 1 } } }]]

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

-- A game in the builder on design "hut" (text `hut`), with prefabs
-- `prefabs` ({ [name] = text }) in the save directory.
local function builder(hut, prefabs)
	_G.love = LoveMock.new()
	assert(DesignStore.write(CFG, "designs", "hut", hut))
	for name, text in pairs(prefabs or {}) do
		assert(DesignStore.write(CFG, "prefabs", name, text))
	end
	local game = GameHarness.startSession(World.new(20, 20), { config = configFor("hut") })
	Fake.tap(game, "b")
	assertEqual("scriptBuilder", game.flow.screen)
	return game, game.flow.scriptBuilder
end

-- Frames in one second.
local SECOND = 60

local function labels(screen)
	local out = {}
	for i, row in ipairs(screen.scene and require("src.game.builder.scene").rows(screen.scene) or {}) do
		out[i] = row.node.name or row.node.id
	end
	return table.concat(out, ",")
end

test("a declarative file changed on disk reloads within a second and stays editable", function()
	local game, screen = builder(HUT)
	assertEqual("root,Base", labels(screen))
	assert(DesignStore.write(CFG, "designs", "hut", (HUT:gsub('"Base"', '"Roof"'))))
	Fake.runUntil(game, function()
		return labels(screen) == "root,Roof"
	end, SECOND)
	assertFalse(screen.locked, "still GUI-editable")
	assertFalse(require("src.app.screens.script_builder").dirty(screen), "the reload is the saved state")
end)

local WIDE = [[local width = UI.number({ default = 2, min = 1, max = 4 })
return box{ id = "base", size = { width, 1, 1 } }
]]

local function param(screen, name)
	for _, p in ipairs(screen.params) do
		if p.name == name then
			return p
		end
	end
end

test("a file given code locks; a changed param default shows in the params and the model", function()
	local game, screen = builder(HUT)
	assert(DesignStore.write(CFG, "designs", "hut", WIDE))
	Fake.runUntil(game, function()
		return param(screen, "width") ~= nil
	end, SECOND)
	assertTrue(screen.locked, "a file with code opens locked")
	assertEqual(2, screen.blueprint.width)
	assert(DesignStore.write(CFG, "designs", "hut", (WIDE:gsub("default = 2", "default = 3"))))
	Fake.runUntil(game, function()
		return param(screen, "width").value == 3
	end, SECOND)
	assertEqual(3, screen.blueprint.width)
end)

test("a prefab changed on disk rebuilds the design placing it", function()
	local lamp = [[return box{ size = { 1, 1, 1 } }]]
	local game, screen = builder([[return group{ prefab("lamp", { id = "lamp1" }) }]], { lamp = lamp })
	assertEqual(1, screen.blueprint.width)
	assert(DesignStore.write(CFG, "prefabs", "lamp", (lamp:gsub("{ 1, 1, 1 }", "{ 3, 1, 1 }"))))
	Fake.runUntil(game, function()
		return screen.blueprint.width == 3
	end, SECOND)
end)

test("unsaved edits survive a change on disk, the message saying so", function()
	local game, screen = builder(HUT)
	-- An edit through the context menu: Duplicate.
	local ScriptBuilderScreen = require("src.app.screens.script_builder")
	local rows = ScriptBuilderScreen.treeRows(screen)
	local base = rows[2]
	Fake.click(game, 2, base.x + 4, base.y + 4)
	local ContextMenu = require("src.app.ui.context_menu")
	for i, item in ipairs(screen.menu.items) do
		if item == "Duplicate" then
			local r = ContextMenu.row(screen.menu, i)
			Fake.click(game, 1, r.x + 4, r.y + 4)
		end
	end
	assertTrue(ScriptBuilderScreen.dirty(screen), "the duplicate is unsaved")
	local edited = labels(screen)
	assert(DesignStore.write(CFG, "designs", "hut", (HUT:gsub('"Base"', '"Roof"'))))
	Fake.runUntil(game, function()
		return screen.message ~= nil and screen.message:find("changed on disk", 1, true) ~= nil
	end, SECOND)
	assertEqual(edited, labels(screen), "the edits are kept")
	assertTrue(ScriptBuilderScreen.dirty(screen))
end)

test("the code panel follows a reload, but unrun code in it is kept", function()
	local TextBuffer = require("src.game.text_buffer")
	local game, screen = builder(HUT)
	Fake.tap(game, "6")
	assert(DesignStore.write(CFG, "designs", "hut", WIDE))
	Fake.runUntil(game, function()
		return screen.locked
	end, SECOND)
	assertEqual(WIDE, TextBuffer.text(screen.code.buffer), "the panel shows the file as it now reads")
	assertTrue(screen.code.open)
	Fake.typeText(game, "-- mine\n")
	assert(DesignStore.write(CFG, "designs", "hut", (WIDE:gsub("default = 2", "default = 3"))))
	Fake.runUntil(game, function()
		return screen.message ~= nil and screen.message:find("changed on disk", 1, true) ~= nil
	end, SECOND)
	assertEqual("-- mine\n" .. WIDE, TextBuffer.text(screen.code.buffer))
end)
