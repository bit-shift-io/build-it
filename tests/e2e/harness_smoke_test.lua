-- Proves the headed path end-to-end: a session boots under real LÖVE 12,
-- frames step and are genuinely drawn, and a capture of the grid and the
-- character lands on disk as a PNG.
local GameHarness = require("tests.support.game_harness")
local FrameStepper = require("tests.support.frame_stepper")
local Capture = require("tests.support.capture")
local Fake = require("tests.support.fake_input")

test("runs on LÖVE 12", function()
	local major = love.getVersion()
	assertEqual(12, major)
end)

test("a session boots, walks and captures a frame with grid and character", function()
	local game = GameHarness.startSession({ width = 40, height = 30 }, { real = true })
	local input = Fake.FakeInput.new()
	local c = game.ctx.pools.characters[1]
	local startX = c.x

	Fake.holdFor(game, input, "d", 1)

	assertTrue(c.x > startX, "expected D to walk the character right")
	assertNear(1.0, game.ctx.time, 0.0001, "expected 60 frames at 1/60s to advance ctx.time by 1 second")

	local path = Capture.capture("walked")
	local file = io.open(path, "rb")
	assertTrue(file ~= nil, "expected a capture at " .. path)
	assertEqual("\137PNG", file:read(4), "expected the capture to be a PNG")
	file:close()
end)
