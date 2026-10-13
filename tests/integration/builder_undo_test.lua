-- The builder's brick set, paint and undo through the real input path:
-- sidebar clicks, keys and modifiers go through src/app/flow.lua to the
-- builder screen. Screen positions come from projecting draft points
-- through the screen's own camera view.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Draft = require("src.game.builder.draft")
local BuilderScreen = require("src.app.screens.builder")
local BuilderCamera = require("src.app.builder_camera")

local function openBuilder()
	_G.love = LoveMock.new()
	local game = GameHarness.startSession({ width = 20, height = 20 })
	local input = Fake.FakeInput.new()
	Fake.tap(game, "b")
	return game, game.flow.builder, input
end

local function pixelOf(builder, x, y, z)
	local sx, sy = BuilderCamera.project(BuilderScreen.view(builder), x, y, z)
	return sx, sy
end

-- The centre of the sidebar button with this label.
local function button(builder, label)
	for _, b in ipairs(BuilderScreen.buttons(builder)) do
		if b.label == label then
			return b.x + b.width / 2, b.y + b.height / 2
		end
	end
	error("no sidebar button " .. label)
end

-- A key tapped with modifier keys held down.
local function chord(game, input, modifiers, key)
	for _, m in ipairs(modifiers) do
		input:press(m)
	end
	Fake.tap(game, key)
	for _, m in ipairs(modifiers) do
		input:release(m)
	end
end

test("place, paint, undo twice, redo once", function()
	local game, builder, input = openBuilder()
	local draft = builder.draft

	Fake.click(game, 1, button(builder, "Stone"))
	Fake.click(game, 1, pixelOf(builder, 2, 2, 0))
	assertEqual(1, #draft.bricks)
	local brick = draft.bricks[1]
	assertEqual("stone", brick.material)
	assertEqual(1, brick.paint)

	-- Pick paint 8, then shift-click the brick's top to paint it.
	Fake.click(game, 1, button(builder, "paint:8"))
	input:press("lshift")
	Fake.click(game, 1, pixelOf(builder, 2, 2, 1))
	input:release("lshift")
	assertEqual(1, #draft.bricks, "expected shift-click to paint, not place")
	assertEqual(8, draft.bricks[1].paint)

	chord(game, input, { "lctrl" }, "z")
	assertEqual(1, #builder.draft.bricks)
	assertEqual(1, builder.draft.bricks[1].paint, "expected the paint undone")
	chord(game, input, { "lctrl" }, "z")
	assertEqual(0, #builder.draft.bricks, "expected the place undone")

	chord(game, input, { "lctrl", "lshift" }, "z")
	assertEqual(1, #builder.draft.bricks, "expected the place redone")
	local redone = builder.draft.bricks[1]
	assertEqual(1, redone.paint)
	assertEqual("stone", redone.material)
	assertEqual(1, redone.x)
	assertEqual(1, redone.y)
	assertEqual(0, redone.z)
end)

test("pick a shape, turn it with R, and place it turned", function()
	local game, builder = openBuilder()
	Fake.click(game, 1, button(builder, "1x4"))
	Fake.tap(game, "r")
	Fake.click(game, 1, pixelOf(builder, 1.5, 2, 0))
	assertEqual(1, #builder.draft.bricks)
	local brick = builder.draft.bricks[1]
	assertEqual("1x4", brick.shape)
	assertEqual(1, brick.rotation)
	assertEqual(1, brick.width)
	assertEqual(4, brick.depth)
	assertEqual(brick, Draft.brickAt(builder.draft, 1, 3, 0))

	Fake.tap(game, "r")
	Fake.tap(game, "r")
	Fake.tap(game, "r")
	assertEqual(0, builder.held.rotation, "expected four turns to come full circle")
end)

test("undo takes back a baseplate resize", function()
	local game, builder, input = openBuilder()
	Fake.click(game, 1, button(builder, "Width +"))
	assertEqual(2, builder.draft.width)
	chord(game, input, { "rctrl" }, "z")
	assertEqual(1, builder.draft.width)
end)
