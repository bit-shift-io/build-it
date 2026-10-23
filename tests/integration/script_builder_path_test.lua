-- The Path tool and Sweep in the script builder through the real input
-- path (src/app/flow.lua): key 3 draws lines, polylines, Béziers,
-- Catmull-Rom splines, arcs and helixes on the work plane; right-click a
-- shape, Sweep, then click a path and the shape sweeps along it.
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

-- The screen pixel where design-space point p (tiles) shows.
local function pixel(screen, p)
	local s, o = screen.cfg.studsPerTile, screen.origin
	return BuilderCamera.project(ScriptBuilderScreen.view(screen), (p[1] - o[1]) * s, (p[2] - o[2]) * s, p[3] * s)
end

-- Left clicks on design-space ground points { x, y }, in order.
local function clickGround(game, screen, points)
	for _, p in ipairs(points) do
		local x, y = pixel(screen, { p[1], p[2], 0 })
		Fake.click(game, 1, x, y)
	end
end

-- Picks the Path menu's row labelled `label`.
local function pickCurve(game, screen, label)
	for _, row in ipairs(assert(ScriptBuilderScreen.shapeMenu(screen))) do
		if row.item.label == label then
			Fake.click(game, 1, row.x + 5, row.y + 5)
			return
		end
	end
	error("no menu row " .. label)
end

local PROFILE = [[
return group{ id = "root", shape{ id = "s", points = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } } } }
]]

test("an arc takes centre, start and end clicks; a polyline takes clicks until Return", function()
	local game, screen = openBuilder("rails", PROFILE)
	Fake.tap(game, "3")
	assertEqual("path", screen.tool)
	pickCurve(game, screen, "Arc")
	clickGround(game, screen, { { 0, 0 }, { 3, 0 }, { 0, 3 } })
	local arc = screen.scene.root.children[2]
	assertEqual("path", arc.kind)
	assertEqual("arc", arc.curve)
	assertEqual(3, arc.radius)
	assertEqual(0, arc.start)
	assertEqual(90, arc.angle)
	assertEqual(arc.id, screen.scene.selection[1])
	assertEqual(1, #screen.history.past, "one undo step")
	pickCurve(game, screen, "Polyline")
	clickGround(game, screen, { { 0.5, 0.5 }, { 2, 0.5 }, { 2, 2 } })
	assertEqual(2, #screen.scene.root.children, "not finished yet")
	assertEqual(3, #screen.shape.drawing.points)
	Fake.tap(game, "return")
	local poly = screen.scene.root.children[3]
	assertEqual("polyline", poly.curve)
	assertEqual(3, #poly.points)
	assertEqual("2 2", table.concat(poly.points[3], " "))
	Fake.tap(game, "escape")
	assertEqual("select", screen.tool)
end)

test("right-click a shape, Sweep, click a path: the shape sweeps along it into a solid, one undo step", function()
	local game, screen = openBuilder("beam", PROFILE)
	Fake.tap(game, "3")
	pickCurve(game, screen, "Arc")
	clickGround(game, screen, { { 0, 0 }, { 3, 0 }, { 0, 3 } })
	Fake.tap(game, "escape")
	local before = #screen.triangles
	local row
	for _, r in ipairs(ScriptBuilderScreen.treeRows(screen)) do
		if r.node.id == "s" then
			row = r
		end
	end
	Fake.click(game, 2, row.x + 10, row.y + 5)
	local index
	for i, item in ipairs(screen.menu.items) do
		if item == "Sweep" then
			index = i
		end
	end
	assertTrue(index, "the menu offers Sweep")
	local r = ContextMenu.row(screen.menu, index)
	Fake.click(game, 1, r.x + 5, r.y + 5)
	assertTrue(screen.sweeping ~= nil, "waiting for a path click")
	local d = math.sqrt(4.5)
	local x, y = pixel(screen, { d, d, 0 })
	Fake.click(game, 1, x + 3, y)
	assertEqual(nil, screen.sweeping)
	local sweep = screen.scene.root.children[1]
	assertEqual("sweep", sweep.kind)
	assertEqual("s", sweep.children[1].id)
	assertEqual("arc", sweep.children[2].curve)
	assertEqual(sweep.id, screen.scene.selection[1])
	assertTrue(#screen.triangles > before, "the sweep has geometry")
	assertEqual(2, #screen.history.past)
	local labels = {}
	for i, p in ipairs(ScriptBuilderScreen.properties(screen)) do
		labels[i] = p.prop.key
	end
	assertEqual("twist startScale endScale", table.concat(labels, " "))
	local saved = assert(Sandbox.run(require("src.game.script.serialize").tree(screen.scene.root), "beam"))
	assertEqual("sweep", saved.root.children[1].kind)
end)

test("Esc drops a Sweep waiting for its path, and a click on no path refuses", function()
	local game, screen = openBuilder("beam", PROFILE)
	local row = ScriptBuilderScreen.treeRows(screen)[2]
	Fake.click(game, 2, row.x + 10, row.y + 5)
	local index
	for i, item in ipairs(screen.menu.items) do
		if item == "Sweep" then
			index = i
		end
	end
	local r = ContextMenu.row(screen.menu, index)
	Fake.click(game, 1, r.x + 5, r.y + 5)
	assertTrue(screen.sweeping ~= nil)
	Fake.tap(game, "escape")
	assertEqual(nil, screen.sweeping)
	assertEqual("scriptBuilder", game.flow.screen)
	Fake.click(game, 2, row.x + 10, row.y + 5)
	r = ContextMenu.row(screen.menu, index)
	Fake.click(game, 1, r.x + 5, r.y + 5)
	clickGround(game, screen, { { 3, 3 } })
	assertEqual(nil, screen.sweeping)
	assertEqual(0, #screen.history.past)
	assertTrue(screen.message ~= nil, "says why")
end)
