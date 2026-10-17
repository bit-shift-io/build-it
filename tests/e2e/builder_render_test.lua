-- The builder under real LÖVE 12: the draft's live mesh drawn through the
-- orbit camera with a depth buffer, beside the sidebar. Captures land in
-- tests/screenshots/builder_render_test/ for eyeballing.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local BuilderScreen = require("src.app.screens.builder")
local BuilderCamera = require("src.app.builder_camera")
local Bricks = require("src.game.builder.bricks")

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

local function clickButton(game, builder, label)
	for _, b in ipairs(BuilderScreen.buttons(builder)) do
		if b.label == label then
			Fake.click(game, 1, b.x + b.width / 2, b.y + b.height / 2)
			return
		end
	end
	error("no sidebar button " .. label)
end

test("plank and stone bricks look different under the same paint", function()
	local game = GameHarness.startSession({ width = 20, height = 20 }, { real = true })
	Fake.tap(game, "b")
	local builder = game.flow.builder
	for _, label in ipairs({ "Width +", "Width +", "Depth +", "Depth +" }) do
		clickButton(game, builder, label)
	end
	clickButton(game, builder, "2x4")
	-- One row per paint: plank on the west, stone on the east.
	local paints = { 1, 11, 8, 12 } -- red, white, blue, black
	for row, paint in ipairs(paints) do
		local y = (row - 1) * 3
		clickButton(game, builder, "paint:" .. paint)
		clickButton(game, builder, "Plank")
		Fake.click(game, 1, pixelOf(builder, 3, y + 1, 0))
		clickButton(game, builder, "Stone")
		Fake.click(game, 1, pixelOf(builder, 9, y + 1, 0))
	end
	assertEqual(2 * #paints, #builder.draft.bricks)
	game:mousemoved(5, 5, 0, 0)
	local pixels = renderFrame(game)
	Capture.capture("plank_vs_stone")

	-- Corresponding points on each pair's top faces differ in pattern.
	for row, paint in ipairs(paints) do
		local y = (row - 1) * 3
		local diff, n = 0, 0
		for i = 0, 6 do
			for j = 0, 3 do
				local px, py = 1.3 + i * 0.5, y + 0.2 + j * 0.45
				local r1, g1, b1 = colorAt(pixels, pixelOf(builder, px, py, 1))
				local r2, g2, b2 = colorAt(pixels, pixelOf(builder, px + 6, py, 1))
				diff = diff + math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2)
				n = n + 1
			end
		end
		assertTrue(diff / n > 0.04, string.format("expected plank and stone to differ under paint %d (mean diff %.3f)", paint, diff / n))
	end
end)

test("every brick shape draws, turned", function()
	local game = GameHarness.startSession({ width = 20, height = 20 }, { real = true })
	Fake.tap(game, "b")
	local builder = game.flow.builder
	for _, label in ipairs({ "Width +", "Width +", "Width +", "Depth +", "Depth +", "Depth +" }) do
		clickButton(game, builder, label)
	end
	-- Each plain shape twice, in its own paint: as authored, and turned a
	-- quarter 4 studs south of it.
	local plain = {}
	for _, shape in ipairs(CFG.bricks) do
		if not (shape.ability or shape.port or shape.storage) then
			table.insert(plain, shape)
		end
	end
	for i, shape in ipairs(plain) do
		clickButton(game, builder, shape.label or shape.name)
		clickButton(game, builder, i % 2 == 1 and "Plank" or "Stone")
		clickButton(game, builder, "paint:" .. i)
		local x = 1 + ((i - 1) % 3) * 5
		local y = math.floor((i - 1) / 3) * 8
		local w, d = Bricks.footprint(shape.name, 0, CFG)
		Fake.click(game, 1, pixelOf(builder, x + w / 2, y + d / 2, 0))
		Fake.tap(game, "r")
		Fake.click(game, 1, pixelOf(builder, x + d / 2, y + 4 + w / 2, 0))
		Fake.tap(game, "r")
		Fake.tap(game, "r")
		Fake.tap(game, "r")
	end
	assertEqual(2 * #plain, #builder.draft.bricks)
	game:mousemoved(5, 5, 0, 0)
	renderFrame(game)
	Capture.capture("shapes")
end)

-- The shapes with a role: function, port and storage bricks.
local function roleShapes()
	local out = {}
	for _, shape in ipairs(CFG.bricks) do
		if shape.ability or shape.port or shape.storage then
			table.insert(out, shape)
		end
	end
	return out
end

test("every function, port and storage brick draws its own model, turned", function()
	local game = GameHarness.startSession({ width = 20, height = 20 }, { real = true })
	Fake.tap(game, "b")
	local builder = game.flow.builder
	-- The 4x4 tile baseplate holds four rows of two shapes, so the shapes
	-- are placed a page at a time, on a fresh design for each.
	local PER_PAGE = 8
	local shapes = roleShapes()
	for page = 1, math.ceil(#shapes / PER_PAGE) do
		if page > 1 then
			clickButton(game, builder, "New")
		end
		for _, label in ipairs({ "Width +", "Width +", "Width +", "Depth +", "Depth +", "Depth +" }) do
			clickButton(game, builder, label)
		end
		-- Zoomed out so the whole 4x4 tile baseplate fits between the panels.
		game:wheelmoved(0, -6)
		-- Placed back (north) to front so no brick hides the next one's studs:
		-- each as authored, and turned a quarter 5 studs east of it.
		for n = 1, PER_PAGE do
			local i = (page - 1) * PER_PAGE + n
			local shape = shapes[i]
			if not shape then
				break
			end
			clickButton(game, builder, shape.label)
			clickButton(game, builder, "paint:" .. (i % 2 == 1 and 4 or 10))
			local x, y = 1 + ((n - 1) % 2) * 9, math.floor((n - 1) / 2) * 4
			local w, d = Bricks.footprint(shape.name, 0, CFG)
			Fake.click(game, 1, pixelOf(builder, x + w / 2, y + d / 2, 0))
			Fake.tap(game, "r")
			Fake.click(game, 1, pixelOf(builder, x + 5 + d / 2, y + w / 2, 0))
			Fake.tap(game, "r")
			Fake.tap(game, "r")
			Fake.tap(game, "r")
			assertEqual(2 * n, #builder.draft.bricks, "expected both " .. shape.name .. " bricks placed")
		end
		game:mousemoved(5, 5, 0, 0)
		renderFrame(game)
		Capture.capture(page == 1 and "function_bricks" or "function_bricks_" .. page)
	end
end)

test("the info panel shows traits, cost red where short, and every broken rule, clear of the sidebar", function()
	-- Storage covers the planks but holds only 3 stone, so stone shows short.
	local game = GameHarness.startSession({ width = 20, height = 20 }, { real = true, storage = { plank = 50, stone = 3 } })
	Fake.tap(game, "b")
	local builder = game.flow.builder
	clickButton(game, builder, "Width +")
	clickButton(game, builder, "Saw bench")
	Fake.click(game, 1, pixelOf(builder, 4, 1, 0))
	clickButton(game, builder, "Input port")
	Fake.click(game, 1, pixelOf(builder, 4, 2.5, 0)) -- off the edge
	clickButton(game, builder, "Stone")
	clickButton(game, builder, "1x2")
	Fake.click(game, 1, pixelOf(builder, 1, 3.5, 0))
	assertEqual(3, #builder.draft.bricks)
	local info = BuilderScreen.info(builder)
	assertEqual(2, #info.problems, "no output port, port off edge")
	local designs = #builder.library.designs
	clickButton(game, builder, "Save")
	assertEqual(designs, #builder.library.designs, "expected the save refused")

	game:mousemoved(5, 5, 0, 0)
	local pixels = renderFrame(game)
	Capture.capture("info_panel")

	-- Nothing in the sidebar runs into the window's bottom edge.
	local _, h = love.graphics.getDimensions()
	local last = BuilderScreen.buttons(builder)
	last = last[#last]
	assertTrue(last.y + last.height < h, "expected the sidebar's last button inside the window")
	-- The panel is drawn: its background, not the 3D view, at its left edge.
	local panel = BuilderScreen.infoPanel(builder)
	local r, g, b = colorAt(pixels, panel.x + 4, h / 2)
	assertTrue(math.abs(r - 0.13) < 0.03 and math.abs(b - 0.16) < 0.03, "expected the info panel background")
end)
