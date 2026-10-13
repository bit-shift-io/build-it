-- The builder through the real input path: key and mouse events go through
-- src/app/flow.lua to the builder screen, which picks with the same camera
-- it draws with. Screen positions come from projecting a stud through that
-- camera -- where a player would see it.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local Draft = require("src.game.builder.draft")
local BuilderScreen = require("src.app.screens.builder")
local BuilderCamera = require("src.app.builder_camera")

local CFG = Config.builder

local function openBuilder()
	_G.love = LoveMock.new()
	local game = GameHarness.startSession({ width = 20, height = 20 })
	Fake.tap(game, "b")
	return game, game.flow.builder
end

-- The screen pixel showing draft point (x, y, z).
local function pixelOf(builder, x, y, z)
	local sx, sy = BuilderCamera.project(BuilderScreen.view(builder), x, y, z)
	return sx, sy
end

test("B opens the builder and Esc returns to the world", function()
	local game = openBuilder()
	assertEqual("builder", game.flow.screen)
	Fake.tap(game, "escape")
	assertEqual("world", game.flow.screen)
end)

test("the world stands still while the builder is open", function()
	local game = openBuilder()
	local input = Fake.FakeInput.new()
	local c = game.ctx.pools.characters[1]
	local x = c.x
	Fake.holdFor(game, input, "d", 0.5)
	assertNear(x, c.x)
end)

test("place three bricks, stacking one, remove one, and leave", function()
	local game, builder = openBuilder()
	local draft = builder.draft

	-- Two side by side on the baseplate's top, one stacked across them.
	Fake.click(game, 1, pixelOf(builder, 1, 2, 0))
	Fake.click(game, 1, pixelOf(builder, 3, 2, 0))
	Fake.click(game, 1, pixelOf(builder, 2, 2, 1))
	assertEqual(3, #draft.bricks)
	local top = Draft.brickAt(draft, 1, 1, 1)
	assertTrue(top, "expected the third brick stacked on layer 1")
	assertEqual(1, top.x)
	assertEqual(1, top.y)

	-- Right-click the stacked brick's top to remove it.
	Fake.click(game, 2, pixelOf(builder, 2, 2, 2))
	assertEqual(2, #draft.bricks)
	assertEqual(nil, Draft.brickAt(draft, 1, 1, 1))

	Fake.tap(game, "escape")
	assertEqual("world", game.flow.screen)
	Fake.tap(game, "b")
	assertEqual(2, #game.flow.builder.draft.bricks, "expected the draft kept between visits")
end)

test("right-dragging orbits the camera without removing a brick", function()
	local game, builder = openBuilder()
	local sx, sy = pixelOf(builder, 2, 2, 0)
	Fake.click(game, 1, sx, sy)
	local yaw = builder.camera.yaw
	Fake.drag(game, 2, sx, sy, sx + 120, sy)
	assertEqual(1, #builder.draft.bricks)
	assertNear(yaw + 120 * CFG.camera.orbitSpeed, builder.camera.yaw)
end)

test("the wheel zooms the builder camera, not the world camera", function()
	local game, builder = openBuilder()
	local distance, zoom = builder.camera.distance, game.camera.zoom
	game:wheelmoved(0, -2)
	assertTrue(builder.camera.distance > distance, "expected the builder camera to back off")
	assertNear(zoom, game.camera.zoom)
end)

-- The centre of the sidebar button with this label.
local function button(builder, label)
	for _, b in ipairs(BuilderScreen.buttons(builder)) do
		if b.label == label then
			return b.x + b.width / 2, b.y + b.height / 2
		end
	end
	error("no sidebar button " .. label)
end

test("the sidebar grows the baseplate, and refuses to shrink it under a brick", function()
	local game, builder = openBuilder()
	Fake.click(game, 1, button(builder, "Width +"))
	assertEqual(2, builder.draft.width)
	Fake.click(game, 1, button(builder, "Depth +"))
	assertEqual(2, builder.draft.depth)

	-- A brick on the second tile column (studs 4-5) blocks shrinking the width.
	Fake.click(game, 1, pixelOf(builder, 5, 1, 0))
	assertEqual(4, builder.draft.bricks[1].x)
	Fake.click(game, 1, button(builder, "Width -"))
	assertEqual(2, builder.draft.width)
	assertTrue(builder.message, "expected the sidebar to say why")
	Fake.click(game, 1, button(builder, "Depth -"))
	assertEqual(1, builder.draft.depth)
end)
