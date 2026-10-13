-- The builder under real LÖVE 12: the draft's live mesh drawn through the
-- orbit camera with a depth buffer, beside the sidebar. Captures land in
-- tests/screenshots/builder_render_test/ for eyeballing.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local BuilderScreen = require("src.app.screens.builder")
local BuilderCamera = require("src.app.builder_camera")

local CFG = Config.builder

-- Renders the game into a window-sized canvas at 1 px per unit and reads it back.
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

local function pixelOf(builder, x, y, z)
	return BuilderCamera.project(BuilderScreen.view(builder), x, y, z)
end

local function colorAt(pixels, x, y)
	return pixels:getPixel(math.floor(x), math.floor(y))
end

-- Bricks are red-dominant, the baseplate green-dominant.
local function isBrick(pixels, x, y)
	local r, g = colorAt(pixels, x, y)
	return r > g + 0.2
end

local function isBaseplate(pixels, x, y)
	local r, g = colorAt(pixels, x, y)
	return g > r + 0.1
end

test("the builder draws a small stack on the baseplate, nearest faces in front", function()
	local game = GameHarness.startSession({ width = 20, height = 20 }, { real = true })
	Fake.tap(game, "b")
	local builder = game.flow.builder
	Fake.click(game, 1, BuilderScreen.buttons(builder)[2].x + 4, BuilderScreen.buttons(builder)[2].y + 4) -- Width +
	Fake.click(game, 1, pixelOf(builder, 2, 2, 0))
	Fake.click(game, 1, pixelOf(builder, 4, 2, 0))
	Fake.click(game, 1, pixelOf(builder, 3, 2, 1))
	Fake.click(game, 1, pixelOf(builder, 3, 2, 2))
	assertEqual(4, #builder.draft.bricks)
	-- Park the cursor off the model so no ghost brick draws.
	game:mousemoved(5, 5, 0, 0)

	local pixels = renderFrame(game)
	Capture.capture("stack")

	assertTrue(isBrick(pixels, pixelOf(builder, 3, 2, 3)), "expected the top brick's top face")
	assertTrue(isBaseplate(pixels, pixelOf(builder, 7.5, 3.5, 0)), "expected bare baseplate in its south-east corner")
	-- The stack hides the baseplate stud right behind its middle.
	assertTrue(isBrick(pixels, pixelOf(builder, 3, 1.5, 0)), "expected the stack to hide the baseplate behind it")
end)

test("orbiting and zooming keep drawing the stack", function()
	local game = GameHarness.startSession({ width = 20, height = 20 }, { real = true })
	Fake.tap(game, "b")
	local builder = game.flow.builder
	Fake.click(game, 1, pixelOf(builder, 2, 2, 0))
	Fake.click(game, 1, pixelOf(builder, 2, 2, 1))
	game:mousemoved(5, 5, 0, 0)

	for _, step in ipairs({ { "orbit_west", -300, 0, 0 }, { "zoomed_in", 0, 0, 30 }, { "steep_zoomed_out", 0, 400, -60 } }) do
		local sx, sy = 700, 400
		if step[2] ~= 0 or step[3] ~= 0 then -- a drag that doesn't move is a right-click
			Fake.drag(game, 2, sx, sy, sx + step[2], sy + step[3])
		end
		game:wheelmoved(0, step[4])
		game:mousemoved(5, 5, 0, 0)
		local pixels = renderFrame(game)
		Capture.capture(step[1])
		assertTrue(isBrick(pixels, pixelOf(builder, 2, 2, 2)), "expected the stack's top in view: " .. step[1])
	end
	assertNear(CFG.camera.maxPitch, builder.camera.pitch)
end)

test("hovering a free spot shows a see-through ghost brick there", function()
	local game = GameHarness.startSession({ width = 20, height = 20 }, { real = true })
	Fake.tap(game, "b")
	local builder = game.flow.builder
	game:mousemoved(5, 5, 0, 0)
	local before = renderFrame(game)
	local sx, sy = pixelOf(builder, 1, 1, 0)
	game:mousemoved(sx, sy, 0, 0)
	local after = renderFrame(game)
	Capture.capture("ghost")

	local r0, g0 = colorAt(before, sx, sy)
	local r1, g1 = colorAt(after, sx, sy)
	assertTrue(r1 - g1 > r0 - g0 + 0.1, "expected the ghost to tint the baseplate red")
	assertEqual(0, #builder.draft.bricks)
end)
