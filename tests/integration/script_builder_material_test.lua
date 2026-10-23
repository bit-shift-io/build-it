-- Materials in the script builder through the real input path
-- (src/app/flow.lua): key 5, or Material in the context menu, opens the
-- material panel under its top bar slot; its rows set the selected nodes'
-- material, texture variant, texture scale and rotation, each one undo
-- step. Changing material changes cost; changing variant doesn't.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
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

-- Clicks the material panel's row of `kind` ("name", "variant", "scale",
-- "rotation") with `value` (names and variants), on `part` (nil, "minus",
-- "plus").
local function clickPanel(game, screen, kind, value, part)
	local rows = assert(ScriptBuilderScreen.materialPanel(screen), "the material panel is open")
	for _, row in ipairs(rows) do
		if row.kind == kind and (value == nil or row.value == value) then
			local box = part and row[part] or row
			Fake.click(game, 1, box.x + box.width / 2, box.y + box.height / 2)
			return
		end
	end
	error("no material row " .. kind .. " " .. tostring(value))
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

test("key 5 opens the material panel; its rows make the selection stone brick, scaled and turned, and save", function()
	local game, screen = openBuilder("hall", DESIGN)
	clickRow(game, screen, "wall")
	Fake.tap(game, "5")
	assertEqual("material", screen.tool)
	local plankCost = screen.blueprint.cost.plank
	assertEqual(nil, screen.blueprint.cost.stone)

	clickPanel(game, screen, "name", "stone")
	assertEqual(nil, screen.message, screen.message)
	local wall = node(screen, "wall")
	assertEqual("stone", wall.material.name)
	assertEqual("polished", wall.material.variant)
	assertEqual(nil, node(screen, "post").material)
	local stoneCost = screen.blueprint.cost.stone
	assertTrue(stoneCost and stoneCost > 0, "the wall costs stone")
	assertTrue(screen.blueprint.cost.plank < plankCost, "the wall no longer costs plank")

	clickPanel(game, screen, "variant", "brick")
	clickPanel(game, screen, "scale", nil, "plus")
	clickPanel(game, screen, "rotation", nil, "plus")
	wall = node(screen, "wall")
	assertEqual("brick", wall.material.variant)
	assertEqual(1.25, wall.material.scale)
	assertEqual(15, wall.material.rotation)
	assertEqual(stoneCost, screen.blueprint.cost.stone, "a variant never changes cost")

	withCtrl(game, "z")
	assertEqual(0, node(screen, "wall").material.rotation, "each change is one undo step")

	withCtrl(game, "s")
	local text = assert(love.filesystem.read(Config.designs.dir .. "/hall.lua"))
	local saved = assert(Sandbox.run(text, "hall")).root
	assertEqual("brick", saved.children[1].material.variant)

	Fake.tap(game, "escape")
	assertEqual(nil, ScriptBuilderScreen.materialPanel(screen))
end)

test("Material in the context menu opens the panel on the node right-clicked", function()
	local game, screen = openBuilder("hut", DESIGN)
	clickRow(game, screen, "post")
	-- The top of the wall, in the view.
	local s, o = screen.cfg.studsPerTile, screen.origin
	local x, y = BuilderCamera.project(ScriptBuilderScreen.view(screen), (1 - o[1]) * s, (0.5 - o[2]) * s, 1 * s)
	Fake.click(game, 2, x, y)
	local menu = assert(screen.menu, "the context menu is open")
	for i, item in ipairs(menu.items) do
		if item == "Material" then
			local r = ContextMenu.row(menu, i)
			Fake.click(game, 1, r.x + r.width / 2, r.y + r.height / 2)
		end
	end
	assertTrue(ScriptBuilderScreen.materialPanel(screen), "the material panel is open")
	clickPanel(game, screen, "name", "stone")
	assertEqual("stone", node(screen, "wall").material.name)
	assertEqual(nil, node(screen, "post").material)
end)
