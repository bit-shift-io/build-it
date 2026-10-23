-- The script builder under real LÖVE 12: the test design (a box and a
-- scaled sphere) drawn through the orbit camera with its footprint square
-- on the ground. Captures land in tests/screenshots/script_builder_render_test/.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local Fake = require("tests.support.fake_input")
local ScriptBuilderScreen = require("src.app.screens.script_builder")
local BuilderCamera = require("src.app.builder_camera")
local Config = require("src.game.config")

local STUDS = Config.builder.studsPerTile

local function renderFrame(game)
	local w, h = love.graphics.getDimensions()
	local canvas = love.graphics.newCanvas(w, h, { dpiscale = 1 })
	love.graphics.push("all")
	love.graphics.setCanvas(canvas)
	love.graphics.clear(love.graphics.getBackgroundColor())
	game:draw()
	love.graphics.pop()
	return love.graphics.readbackTexture(canvas)
end

-- The pixel showing tile-space point (x, y, z).
local function pixelOf(screen, x, y, z)
	local sx, sy = BuilderCamera.project(ScriptBuilderScreen.view(screen), x * STUDS, y * STUDS, z * STUDS)
	return math.floor(sx), math.floor(sy)
end

local function colorAt(pixels, x, y)
	return pixels:getPixel(x, y)
end

-- The design's default colour is warm (red over blue); the footprint green.
local function isModel(pixels, x, y)
	local r, _, b = colorAt(pixels, x, y)
	return r > b + 0.05
end

local function isFootprint(pixels, x, y)
	local r, g = colorAt(pixels, x, y)
	return g > r + 0.1
end

test("B shows the test design's box and sphere on their footprint square", function()
	local game = GameHarness.startSession({ width = 20, height = 20 }, { real = true })
	Fake.tap(game, "b")
	local screen = game.flow.scriptBuilder
	assertEqual(nil, screen.message, screen.message)
	local f = screen.footprint
	assertEqual(2, f.width)
	assertEqual(2, f.depth)

	local pixels = renderFrame(game)
	Capture.capture("test_design")

	assertTrue(isModel(pixels, pixelOf(screen, 1, 0.75, 1.4)), "expected the sphere's top")
	assertTrue(isModel(pixels, pixelOf(screen, 0.2, 1.5, 0.5)), "expected the box's south face")
	-- The box is 1.5 tiles deep and the footprint rounds that up to 2, so
	-- its south-east corner, nearest the camera, is bare footprint.
	assertTrue(isFootprint(pixels, pixelOf(screen, f.x + f.width - 0.1, f.y + f.depth - 0.1, 0)), "expected the footprint's south-east corner")
end)

test("orbiting and zooming keep drawing the design", function()
	local game = GameHarness.startSession({ width = 20, height = 20 }, { real = true })
	Fake.tap(game, "b")
	local screen = game.flow.scriptBuilder
	Fake.drag(game, 2, 600, 400, 760, 360)
	game:wheelmoved(0, 2)
	local pixels = renderFrame(game)
	Capture.capture("orbited")
	assertTrue(isModel(pixels, pixelOf(screen, 1, 0.75, 1.4)), "expected the sphere's top after orbiting")
end)

test("the Insert menu and the properties strip draw over the view, and an inserted cone shows", function()
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.scriptBuilder = {}
	for k, v in pairs(Config.scriptBuilder) do
		config.scriptBuilder[k] = v
	end
	config.scriptBuilder.testDesign = "e2e_insert.lua"
	assert(love.filesystem.write("e2e_insert.lua", 'return group{ id = "root", box{ id = "base", size = { 2, 2, 0.25 } } }\n'))
	local game = GameHarness.startSession({ width = 20, height = 20 }, { real = true, config = config })
	Fake.tap(game, "b")
	local screen = game.flow.scriptBuilder
	assertEqual(false, screen.locked)
	Fake.tap(game, "4")
	local rows = assert(ScriptBuilderScreen.insertMenu(screen))
	local cone = rows[4]
	assertEqual("Cone", cone.item.label)
	Fake.click(game, 1, cone.x + 10, cone.y + 5)
	local pixels = renderFrame(game)
	Capture.capture("insert_menu")
	local r, g, b = colorAt(pixels, rows[#rows].x + 140, rows[#rows].y + 10)
	assertTrue(r < 0.2 and g < 0.2 and b < 0.2, "expected the menu's dark panel")
	Fake.click(game, 1, pixelOf(screen, 1, 1, 0))
	assertEqual("cone", screen.scene.root.children[2].kind)
	local fields = ScriptBuilderScreen.properties(screen)
	assertEqual(3, #fields)
	Fake.click(game, 1, fields[1].x + 4, fields[1].y + 4)
	pixels = renderFrame(game)
	Capture.capture("properties_strip")
	-- The selected cone is tinted, so any lit surface counts; off the gizmo's
	-- z handle up its middle.
	local cr, cg, cb = colorAt(pixels, pixelOf(screen, 1.25, 1, 0.3))
	assertTrue(cr + cg + cb > 0.9, "expected the cone's side")
	love.filesystem.remove("e2e_insert.lua")
end)

test("a shape drawn with the Shape tool shows as an outline over the view, the grid under the pointer", function()
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.scriptBuilder = {}
	for k, v in pairs(Config.scriptBuilder) do
		config.scriptBuilder[k] = v
	end
	config.scriptBuilder.testDesign = "e2e_shape.lua"
	assert(love.filesystem.write("e2e_shape.lua", 'return group{ id = "root", box{ id = "base", size = { 2, 2, 0.25 } } }\n'))
	local game = GameHarness.startSession({ width = 20, height = 20 }, { real = true, config = config })
	Fake.tap(game, "b")
	local screen = game.flow.scriptBuilder
	Fake.tap(game, "2")
	for _, p in ipairs({ { 0.5, 0.5 }, { 1.5, 0.5 }, { 1.5, 1.5 }, { 0.5, 1.5 }, { 0.5, 0.5 } }) do
		Fake.click(game, 1, pixelOf(screen, p[1], p[2], 0))
	end
	assertEqual("shape", screen.scene.root.children[2].kind, tostring(screen.message))
	local pixels = renderFrame(game)
	Capture.capture("shape_outline")
	-- The selected outline is orange: somewhere round the middle of its
	-- north side.
	local mx, my = pixelOf(screen, 1, 0.5, 0)
	local found = false
	for dx = -2, 2 do
		for dy = -2, 2 do
			local r, g, b = colorAt(pixels, mx + dx, my + dy)
			if r > 0.9 and g > 0.5 and g < 0.8 and b < 0.35 then
				found = true
			end
		end
	end
	assertTrue(found, "expected the selected outline's orange")
	love.filesystem.remove("e2e_shape.lua")
end)

test("a rect swept along an arc renders as a closed curved beam", function()
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.scriptBuilder = {}
	for k, v in pairs(Config.scriptBuilder) do
		config.scriptBuilder[k] = v
	end
	config.scriptBuilder.testDesign = "e2e_sweep.lua"
	assert(love.filesystem.write("e2e_sweep.lua", [[
return group{ id = "root", sweep{ id = "beam", shape{ points = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } } },
	path{ curve = "arc", radius = 3, angle = 90, plane = { origin = { 0, 0, 0.5 }, u = { 1, 0, 0 }, v = { 0, 1, 0 } } } } }
]]))
	local game = GameHarness.startSession({ width = 20, height = 20 }, { real = true, config = config })
	Fake.tap(game, "b")
	local screen = game.flow.scriptBuilder
	assertEqual(nil, screen.message, screen.message)
	assertTrue(#screen.triangles > 0)
	local pixels = renderFrame(game)
	Capture.capture("sweep_beam")
	-- The beam's top half way round the arc, and its outer wall there.
	local o, d = screen.origin, 3 * math.sqrt(0.5)
	assertTrue(isModel(pixels, pixelOf(screen, d - o[1], d - o[2], 1)), "expected the beam's top")
	-- Inside the curve, by the arc's centre, the footprint's north-west
	-- corner is bare.
	assertTrue(isFootprint(pixels, pixelOf(screen, 0.15, 0.15, 0)), "expected bare footprint inside the curve")
	love.filesystem.remove("e2e_sweep.lua")
end)
