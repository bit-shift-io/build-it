-- Move, rotate and scale in the script builder through the real input
-- path (src/app/flow.lua): G, R and S with X, Y and Z axis keys, and the
-- gizmo's handles. Each transform is one undo step and saves into the
-- node's transform.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local Sandbox = require("src.game.script.sandbox")
local ScriptBuilderScreen = require("src.app.screens.script_builder")
local BuilderCamera = require("src.app.builder_camera")

local YARD = [[
return group{ id = "root",
	box{ id = "base", size = { 2, 2, 1 } },
	box{ id = "post", size = { 0.5, 0.5, 2 } },
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

local function clickRow(game, screen, id)
	for _, row in ipairs(ScriptBuilderScreen.treeRows(screen)) do
		if row.node.id == id then
			Fake.click(game, 1, row.x + row.width / 2, row.y + row.height / 2)
			return
		end
	end
	error("no row for " .. id)
end

-- The screen pixel where point p (tiles, the view's space) shows.
local function pixel(screen, p)
	local s = screen.cfg.studsPerTile
	return BuilderCamera.project(ScriptBuilderScreen.view(screen), p[1] * s, p[2] * s, p[3] * s)
end

-- The pointer gliding from where it is to (x, y) over a few moves, no
-- button held.
local function glide(game, screen, x, y)
	local x0, y0 = screen.mouse.x, screen.mouse.y
	for i = 1, 4 do
		local nx, ny = x0 + (x - x0) * i / 4, y0 + (y - y0) * i / 4
		game:mousemoved(nx, ny, nx - x0, ny - y0)
		x0, y0 = nx, ny
	end
end

local function withCtrl(game, key)
	local input = Fake.FakeInput.new()
	input:press("lctrl")
	Fake.tap(game, key)
	input:release("lctrl")
end

-- Node `id` of the design file `name` as saved.
local function savedNode(name, id)
	local text = assert(love.filesystem.read(Config.designs.dir .. "/" .. name .. ".lua"))
	local root = assert(Sandbox.run(text, name)).root
	for _, node in ipairs(root.children) do
		if node.id == id then
			return node
		end
	end
end

-- The post's centre: half its 0.5 tile square, half its 2 tiles up.
local POST = { 0.25, 0.25, 1 }

test("G, X, a drag and a click move a box one tile east in the saved file", function()
	local game, screen = openBuilder("yard", YARD)
	clickRow(game, screen, "post")
	local px, py = pixel(screen, POST)
	game:mousemoved(px, py, 0, 0)
	Fake.tap(game, "g")
	Fake.tap(game, "x")
	local x, y = pixel(screen, { POST[1] + 1, POST[2] + 0.3, POST[3] })
	glide(game, screen, x, y)
	Fake.click(game, 1, x, y)
	assertEqual(nil, screen.transform)
	withCtrl(game, "s")
	local move = savedNode("yard", "post").transform.move
	assertEqual(1, move[1])
	assertEqual(0, move[2])
	assertEqual(0, move[3])
end)

test("the footprint follows a move live; Esc drops it and leaves the builder open", function()
	local game, screen = openBuilder("yard", YARD)
	clickRow(game, screen, "post")
	local px, py = pixel(screen, POST)
	game:mousemoved(px, py, 0, 0)
	Fake.tap(game, "g")
	Fake.tap(game, "x")
	glide(game, screen, pixel(screen, { POST[1] + 3, POST[2], POST[3] }))
	assertEqual(4, screen.footprint.width)
	Fake.tap(game, "escape")
	assertEqual("scriptBuilder", game.flow.screen)
	assertEqual(nil, screen.transform)
	assertEqual(2, screen.footprint.width)
	assertEqual(0, #screen.history.past)
end)

test("a kept transform is one undo step", function()
	local game, screen = openBuilder("yard", YARD)
	clickRow(game, screen, "post")
	local px, py = pixel(screen, POST)
	game:mousemoved(px, py, 0, 0)
	Fake.tap(game, "g")
	Fake.tap(game, "y")
	glide(game, screen, pixel(screen, { POST[1], POST[2] + 2, POST[3] }))
	Fake.tap(game, "return")
	assertEqual(3, screen.footprint.depth)
	assertEqual(1, #screen.history.past)
	withCtrl(game, "z")
	assertEqual(2, screen.footprint.depth)
end)

test("dragging the gizmo's x handle moves the selection along x", function()
	local game, screen = openBuilder("yard", YARD)
	clickRow(game, screen, "post")
	local handles = assert(ScriptBuilderScreen.gizmo(screen))
	assertEqual("x", handles[1].axis)
	-- Halfway along the x handle, then a tile further east.
	local half = POST[1] + 0.5 * 1.25
	local x1, y1 = pixel(screen, { half, POST[2], POST[3] })
	local x2, y2 = pixel(screen, { half + 1, POST[2], POST[3] })
	Fake.drag(game, 1, x1, y1, x2, y2)
	assertEqual(nil, screen.transform)
	assertEqual(1, #screen.history.past)
	withCtrl(game, "s")
	assertEqual(1, savedNode("yard", "post").transform.move[1])
end)

test("R turns the selection about z in 15 degree steps", function()
	local game, screen = openBuilder("yard", YARD)
	clickRow(game, screen, "post")
	local px, py = pixel(screen, { POST[1] + 1, POST[2], POST[3] })
	game:mousemoved(px, py, 0, 0)
	Fake.tap(game, "r")
	local a = math.rad(50)
	local x, y = pixel(screen, { POST[1] + math.cos(a), POST[2] + math.sin(a), POST[3] })
	glide(game, screen, x, y)
	Fake.click(game, 1, x, y)
	withCtrl(game, "s")
	assertEqual(45, savedNode("yard", "post").transform.rotate[3])
end)

test("a locked script refuses G", function()
	local game, screen = openBuilder("posts", [[
local posts = {}
for i = 1, 2 do
	posts[i] = box{ id = "post" .. i, transform = { move = { i, 0, 0 } } }
end
return group{ id = "root", unpack(posts) }
]])
	clickRow(game, screen, "post1")
	Fake.tap(game, "g")
	assertEqual(nil, screen.transform)
	assertTrue(screen.message and screen.message:find("Locked", 1, true), tostring(screen.message))
	assertEqual(nil, ScriptBuilderScreen.gizmo(screen))
end)

test("a prefab instance moves as one; its own nodes stay out of the file", function()
	local game, screen = openBuilder("dorm", [[
return group{ id = "root",
	box{ id = "floor", size = { 3, 3, 0.25 } },
	prefab("bed", { id = "cot" }),
}
]])
	assertEqual(nil, screen.message, screen.message)
	local cot
	for _, target in ipairs(screen.targets) do
		if target.id == "cot" then
			cot = target.triangles[1]
		end
	end
	local sx, sy = pixel(screen, { cot.x, cot.y, cot.z })
	clickRow(game, screen, "cot")
	assertEqual("cot", screen.scene.selection[1])
	game:mousemoved(sx, sy, 0, 0)
	Fake.tap(game, "g")
	Fake.tap(game, "x")
	glide(game, screen, pixel(screen, { cot.x + 1, cot.y, cot.z }))
	Fake.tap(game, "return")
	withCtrl(game, "s")
	local saved = savedNode("dorm", "cot")
	assertEqual(1, saved.transform.move[1])
	assertEqual(0, #saved.children)
end)
