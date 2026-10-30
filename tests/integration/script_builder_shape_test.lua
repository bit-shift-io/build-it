-- The Shape tool in the script builder through the real input path
-- (src/app/flow.lua): key 2 draws rects, ellipses, polygons and paths on
-- the work plane; clicking the first point closes the outline into a shape
-- node, saved as shape{ points = { ... } } and editable when reopened.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local Sandbox = require("src.game.script.sandbox")
local ScriptBuilderScreen = require("src.app.screens.script_builder")
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

-- Left clicks on design-space ground points { x, y }, in order.
local function clickGround(game, screen, points)
	for _, p in ipairs(points) do
		local x, y = pixel(screen, { p[1], p[2], 0 })
		Fake.click(game, 1, x, y)
	end
end

local function withCtrl(game, key)
	local input = Fake.FakeInput.new()
	input:press("lctrl")
	Fake.tap(game, key)
	input:release("lctrl")
end

-- The design file `name` as saved.
local function savedText(name)
	return assert(love.filesystem.read(Config.designs.dir .. "/" .. name .. ".lua"))
end

test("four clicks and a click on the first point close a shape of four hard points, saved and reopened editable", function()
	local game, screen = openBuilder("plot", EMPTY)
	Fake.tap(game, "1")
	assertEqual("draw", screen.tool)
	clickGround(game, screen, { { 0, 0 }, { 2, 0 }, { 2, 1 }, { 0, 1 }, { 0, 0 } })
	local shape = screen.scene.root.children[1]
	assertTrue(shape ~= nil, "a node was added")
	assertEqual("shape", shape.kind)
	assertEqual(4, #shape.points)
	for _, p in ipairs(shape.points) do
		assertEqual(2, #p, "a hard point")
	end
	assertEqual("2 1", table.concat(shape.points[3], " "))
	assertEqual(shape.id, screen.scene.selection[1])
	assertEqual(1, #screen.history.past, "one undo step")
	withCtrl(game, "s")
	local text = savedText("plot")
	assertTrue(text:find("shape{", 1, true) ~= nil, text)
	local root = assert(Sandbox.run(text, "plot")).root
	assertEqual(4, #root.children[1].points)
	-- Reopened: the shape is there and editable.
	Fake.tap(game, "escape")
	Fake.tap(game, "escape")
	assertEqual("world", game.flow.screen)
	Fake.tap(game, "b")
	assertFalse(screen.locked)
	assertEqual("shape", screen.scene.root.children[1].kind)
	assertEqual(4, #screen.scene.root.children[1].points)
end)

test("a path point dragged while placed turns smooth with Bézier handles; a rect takes two corner clicks", function()
	local game, screen = openBuilder("arch", EMPTY)
	Fake.tap(game, "1")
	clickGround(game, screen, { { 0, 0 } })
	local ax, ay = pixel(screen, { 2, 0, 0 })
	local bx, by = pixel(screen, { 2, 1, 0 })
	Fake.drag(game, 1, ax, ay, bx, by)
	clickGround(game, screen, { { 1, 2 }, { 0, 0 } })
	local path = screen.scene.root.children[1]
	assertEqual(3, #path.points)
	assertEqual("2 0 0 1", table.concat(path.points[2], " "))
	assertEqual(2, #path.points[3], "a plain click is a hard point")
	-- Rect, from the Shape menu.
	local rows = assert(ScriptBuilderScreen.shapeMenu(screen))
	assertEqual("Shapes (closed)", rows[1].item.label)
	assertEqual("Rect", rows[2].item.label)
	Fake.click(game, 1, rows[2].x + 5, rows[2].y + 5)
	clickGround(game, screen, { { 4, 3 }, { 3, 2.5 } })
	local rect = screen.scene.root.children[2]
	assertEqual("shape", rect.kind)
	assertEqual("3,2.5 4,2.5 4,3 3,3", (function()
		local parts = {}
		for i, p in ipairs(rect.points) do
			parts[i] = p[1] .. "," .. p[2]
		end
		return table.concat(parts, " ")
	end)())
	assertEqual(2, #screen.history.past)
end)

test("a closed shape's point drags along its plane as one undo step, and the Select tool can do it too", function()
	local game, screen = openBuilder("plot", [[
return group{ id = "root", shape{ id = "s", points = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } } } }
]])
	assertFalse(screen.locked)
	local row = ScriptBuilderScreen.treeRows(screen)[2]
	Fake.click(game, 1, row.x + 10, row.y + 5)
	assertEqual("s", screen.scene.selection[1])
	local ax, ay = pixel(screen, { 1, 1, 0 })
	local bx, by = pixel(screen, { 1.5, 1.25, 0 })
	Fake.drag(game, 1, ax, ay, bx, by)
	local s = screen.scene.root.children[1]
	assertEqual("1.5 1.25", table.concat(s.points[3], " "))
	assertEqual(1, #screen.history.past)
	withCtrl(game, "z")
	assertEqual("1 1", table.concat(screen.scene.root.children[1].points[3], " "))
end)

-- Clicks the Work plane section's button for `plane`.
local function pickPlane(game, screen, plane)
	for _, b in ipairs(assert(ScriptBuilderScreen.workPlane(screen), "the section shows").buttons) do
		if b.plane == plane then
			Fake.click(game, 1, b.x + b.width / 2, b.y + b.height / 2)
			return
		end
	end
	error("no plane button " .. plane)
end

-- Clicks the section's Height - (step -1) or + (step 1) box.
local function stepHeight(game, screen, step)
	local s = assert(ScriptBuilderScreen.workPlane(screen).stepper, "an axis plane shows a stepper")
	local box = step > 0 and s.plus or s.minus
	Fake.click(game, 1, box.x + box.width / 2, box.y + box.height / 2)
end

test("picking a kind closes the Draw menu, and two view clicks make a rect with it closed", function()
	local game, screen = openBuilder("plot", EMPTY)
	Fake.tap(game, "1")
	local rows = assert(ScriptBuilderScreen.shapeMenu(screen))
	for _, r in ipairs(rows) do
		assertTrue(r.item.plane == nil, "the menu lists kinds only")
	end
	Fake.click(game, 1, rows[2].x + 5, rows[2].y + 5)
	assertEqual(nil, ScriptBuilderScreen.shapeMenu(screen))
	assertEqual("draw", screen.tool)
	clickGround(game, screen, { { 4, 3 }, { 3, 2.5 } })
	assertEqual("shape", screen.scene.root.children[1].kind)
	-- Draw again returns to select; picking it from select shows the menu again.
	Fake.tap(game, "1")
	assertEqual("select", screen.tool)
	Fake.tap(game, "1")
	assertTrue(ScriptBuilderScreen.shapeMenu(screen) ~= nil)
end)

test("the Work plane section picks XZ and steps its height; Esc drops a drawing before the tool", function()
	local game, screen = openBuilder("wall", [[
return group{ id = "root", box{ id = "b", size = { 2, 2, 1 } } }
]])
	assertEqual(nil, ScriptBuilderScreen.workPlane(screen), "hidden while neither tool is on")
	Fake.tap(game, "1")
	assertEqual(nil, ScriptBuilderScreen.workPlane(screen).stepper, "ground has no height")
	pickPlane(game, screen, "XZ")
	assertEqual("XZ", screen.planeName)
	stepHeight(game, screen, 1)
	assertEqual(0.25, screen.planeHeight)
	assertEqual(0.25, screen.plane.origin[2])
	Fake.tap(game, "]")
	assertEqual(0.5, screen.planeHeight, "the keys still step")
	stepHeight(game, screen, -1)
	assertEqual(0.25, screen.planeHeight)
	-- Draw on it.
	Fake.click(game, 1, pixel(screen, { 0, 0.25, 0 }))
	assertTrue(screen.shape.drawing ~= nil)
	Fake.tap(game, "escape")
	assertEqual(nil, screen.shape.drawing)
	assertEqual("draw", screen.tool)
	Fake.tap(game, "escape")
	assertEqual("select", screen.tool)
	assertEqual(nil, ScriptBuilderScreen.workPlane(screen))
end)

test("shapes draw on an XZ plane raised with ], and on a face of the model picked in the section", function()
	local game, screen = openBuilder("wall", [[
return group{ id = "root", box{ id = "b", size = { 2, 2, 1 } } }
]])
	Fake.tap(game, "1")
	pickPlane(game, screen, "XZ")
	Fake.tap(game, "]")
	Fake.tap(game, "]")
	assertEqual(0.5, screen.planeHeight)
	-- On the plane y = 0.5: points (x, z).
	local function onPlane(points, y)
		local out = {}
		for i, p in ipairs(points) do
			out[i] = { p[1], y, p[2] }
		end
		return out
	end
	for _, p in ipairs(onPlane({ { 0, 0.25 }, { 1, 0.25 }, { 1, 1 }, { 0, 0.25 } }, 0.5)) do
		Fake.click(game, 1, pixel(screen, p))
	end
	local tri = screen.scene.root.children[2]
	assertEqual("shape", tri.kind, tostring(screen.message))
	assertEqual("0 0.5 0", table.concat(tri.plane.origin, " "))
	assertEqual("0 0 1", table.concat(tri.plane.v, " "))
	assertEqual("1 1", table.concat(tri.points[3], " "))
	-- Pick the box's top face, then draw a triangle on it.
	pickPlane(game, screen, "Face")
	assertTrue(screen.shape.picking)
	-- A click on the section's own height row never ends picking.
	local col = ScriptBuilderScreen.workPlane(screen)
	Fake.click(game, 1, col.buttons[5].x + 2, col.buttons[5].y + 2)
	assertTrue(screen.shape.picking, "a click on the section keeps picking")
	Fake.click(game, 1, pixel(screen, { 1, 1, 1 }))
	assertEqual("Face", screen.planeName)
	assertEqual("0 0 1", table.concat(screen.plane.origin, " "))
	for _, p in ipairs({ { 0.5, 0.5, 1 }, { 1.5, 0.5, 1 }, { 1, 1.5, 1 }, { 0.5, 0.5, 1 } }) do
		Fake.click(game, 1, pixel(screen, p))
	end
	local top = screen.scene.root.children[3]
	assertEqual("shape", top.kind, tostring(screen.message))
	assertEqual(1, top.plane.origin[3])
	assertEqual("1.5 0.5", table.concat(top.points[2], " "))
end)

test("a click within 10 px of an outline, or inside it, selects the shape; 15 px off selects nothing; hover lights it", function()
	local game, screen = openBuilder("plot", [[
return group{ id = "root", shape{ id = "s", points = { { 0, 0 }, { 2, 0 }, { 2, 2 }, { 0, 2 } } } }
]])
	local x, y = pixel(screen, { 1, 0, 0 })
	game:mousemoved(x, y + 8, 0, 0)
	assertEqual("s", screen.hoverOutline)
	assertTrue(ScriptBuilderScreen.overlay(screen).outlines[1].hovered)
	Fake.click(game, 1, x, y + 8)
	assertEqual("s", screen.scene.selection[1])
	Fake.click(game, 1, x, y - 40)
	assertEqual(nil, screen.scene.selection[1])
	game:mousemoved(x, y - 15, 0, 0)
	assertEqual(nil, screen.hoverOutline)
	local cx, cy = pixel(screen, { 1, 1, 0 })
	Fake.click(game, 1, cx, cy)
	assertEqual("s", screen.scene.selection[1])
end)

local function doubleClickGround(game, screen, p)
	local x, y = pixel(screen, { p[1], p[2], 0 })
	game:mousemoved(x, y, 0, 0)
	for _ = 1, 2 do
		game:mousepressed(x, y, 1)
		game:mousereleased(x, y, 1)
	end
	game:update(1 / 60)
end

test("Return closes a polygon of three points; fewer than three refuses with a message", function()
	local game, screen = openBuilder("ret", EMPTY)
	Fake.tap(game, "1")
	clickGround(game, screen, { { 0, 0 }, { 2, 0 } })
	Fake.tap(game, "return")
	assertEqual(0, #screen.scene.root.children)
	assertTrue(screen.message ~= nil and screen.message:find("Can't close"), "refused with a message")
	clickGround(game, screen, { { 2, 2 } })
	Fake.tap(game, "return")
	local shape = screen.scene.root.children[1]
	assertEqual("shape", shape.kind)
	assertEqual(3, #shape.points)
	assertEqual(nil, screen.shape.drawing)
end)

test("a double-click on the last point closes the polygon without adding a point", function()
	local game, screen = openBuilder("dbl", EMPTY)
	Fake.tap(game, "1")
	clickGround(game, screen, { { 0, 0 }, { 2, 0 } })
	doubleClickGround(game, screen, { 2, 2 })
	local shape = screen.scene.root.children[1]
	assertEqual("shape", shape.kind)
	assertEqual(3, #shape.points)
	assertEqual(1, #screen.scene.root.children)
end)

test("a double-click after three points closes it on the first press's duplicate", function()
	local game, screen = openBuilder("dbl3", EMPTY)
	Fake.tap(game, "1")
	clickGround(game, screen, { { 0, 0 }, { 2, 0 }, { 2, 2 } })
	doubleClickGround(game, screen, { 2, 2 })
	assertEqual(3, #screen.scene.root.children[1].points)
end)

test("the first point lights when the pointer is over it, and a hint shows per kind", function()
	local game, screen = openBuilder("hint", EMPTY)
	Fake.tap(game, "1")
	clickGround(game, screen, { { 0, 0 }, { 2, 0 }, { 2, 2 } })
	local x, y = pixel(screen, { 0, 0, 0 })
	game:mousemoved(x + 20, y, 0, 0)
	assertEqual(false, ScriptBuilderScreen.overlay(screen).points[1].lit)
	game:mousemoved(x + 3, y, 0, 0)
	local first = ScriptBuilderScreen.overlay(screen).points[1]
	assertEqual(true, first.first)
	assertEqual(true, first.lit)
	assertTrue(ScriptBuilderScreen.hint(screen):find("Enter or double%-click to close"), "polygon hint")
end)
