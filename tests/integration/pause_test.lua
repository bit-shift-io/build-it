-- P pauses the world through the real input path: while paused the
-- session does not step, so held keys move nothing; P again resumes.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")

local WORLD = { width = 40, height = 30 }

local function start()
	_G.love = LoveMock.new()
	local game = GameHarness.startSession(WORLD)
	return game, Fake.FakeInput.new(), game.ctx.pools.characters[1]
end

test("while paused, holding D does not move the character or advance time", function()
	local game, input, c = start()
	local startX = c.x
	Fake.tap(game, "p")

	Fake.holdFor(game, input, "d", 1)

	assertNear(startX, c.x)
	assertNear(0, game.ctx.time)
end)

test("pressing P again resumes the session", function()
	local game, input, c = start()
	local startX = c.x
	Fake.tap(game, "p")
	Fake.tap(game, "p")

	Fake.holdFor(game, input, "d", 1)

	assertNear(startX + Config.character.speed, c.x, 0.0001)
end)
