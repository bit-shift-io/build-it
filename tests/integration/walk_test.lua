-- Walks the character through the real input path: FakeInput holds WASD keys
-- on a mocked `love.keyboard`, src/app/input.lua turns them into intents,
-- and Session.step moves the character -- the same chain the real app runs.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local FrameStepper = require("tests.support.frame_stepper")

local WORLD = { width = 40, height = 30 }

local function startWalking()
	_G.love = LoveMock.new()
	local game = GameHarness.startSession(WORLD)
	return game, Fake.FakeInput.new(), game.ctx.pools.characters[1]
end

test("holding D for one second walks the character right by its speed", function()
	local game, input, c = startWalking()
	local startX, startY = c.x, c.y

	Fake.holdFor(game, input, "d", 1)

	assertNear(startX + Config.character.speed, c.x, 0.0001)
	assertNear(startY, c.y)
end)

test("W, A and S walk up, left and down", function()
	local game, input, c = startWalking()
	local startX, startY = c.x, c.y
	local half = Config.character.speed / 2

	Fake.holdFor(game, input, "w", 0.5)
	assertNear(startY - half, c.y, 0.0001)

	Fake.holdFor(game, input, "a", 0.5)
	assertNear(startX - half, c.x, 0.0001)

	Fake.holdFor(game, input, "s", 0.5)
	assertNear(startY, c.y, 0.0001)
end)

test("releasing the key stops the character", function()
	local game, input, c = startWalking()

	Fake.holdFor(game, input, "d", 0.5)
	local stoppedX = c.x
	FrameStepper.step(game, 30)

	assertNear(stoppedX, c.x)
end)

test("the camera follows the walking character", function()
	local game, input, c = startWalking()

	Fake.holdFor(game, input, "d", 1)

	assertNear(c.x, game.camera.x)
	assertNear(c.y, game.camera.y)
end)
