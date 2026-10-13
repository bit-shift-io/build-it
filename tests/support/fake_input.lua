-- Drives a fake keyboard/joystick state the way a human would: press/release
-- keys. Built on top of the *current* global `love` (the integration tier's
-- love_mock, or real LÖVE under the e2e tier) so construct a FakeInput only
-- once a `love` global exists (set `_G.love = LoveMock.new()` first in the
-- integration tier).
--
-- Shims love.keyboard.isDown and love.joystick.getJoysticks.
local FrameStepper = require("tests.support.frame_stepper")

local FakeInput = {}
FakeInput.__index = FakeInput

function FakeInput.new()
	local state = love._state or { keysDown = {}, joysticks = {} }
	love._state = state

	love.keyboard.isDown = function(key)
		return state.keysDown[key] == true
	end

	love.joystick = love.joystick or {}
	love.joystick.getJoysticks = function()
		return state.joysticks
	end

	return setmetatable({ state = state }, FakeInput)
end

-- A fake gamepad. Buttons and axes use LÖVE's gamepad names ("a", "dpleft",
-- "leftx"); drive it with :press/:release/:setAxis.
function FakeInput:addJoystick(name)
	local buttons, axes = {}, {}
	local joystick = { connected = true }
	function joystick:isConnected() return self.connected end
	function joystick:getName() return name or "fake pad" end
	function joystick:isGamepadDown(button) return buttons[button] == true end
	function joystick:getGamepadAxis(axis) return axes[axis] or 0 end
	function joystick:press(button) buttons[button] = true end
	function joystick:release(button) buttons[button] = nil end
	function joystick:setAxis(axis, value) axes[axis] = value end
	table.insert(self.state.joysticks, joystick)
	return joystick
end

function FakeInput:removeJoystick(joystick)
	joystick.connected = false
	for i, j in ipairs(self.state.joysticks) do
		if j == joystick then
			table.remove(self.state.joysticks, i)
			return
		end
	end
end

function FakeInput:press(key)
	self.state.keysDown[key] = true
end

function FakeInput:release(key)
	self.state.keysDown[key] = nil
end

-- press, step frames at a fixed 1/60s for `seconds`, then release.
local function holdFor(game, controller, key, seconds)
	controller:press(key)
	FrameStepper.step(game, FrameStepper.secondsToFrames(seconds))
	controller:release(key)
end

-- steps frames until predicate() is true, or fails the test if maxFrames is
-- exhausted without it becoming true.
local function runUntil(game, predicate, maxFrames)
	for _ = 1, maxFrames do
		FrameStepper.step(game, 1)
		if predicate() then
			return
		end
	end
	error(string.format("runUntil: predicate not satisfied within %d frames", maxFrames))
end

return {
	FakeInput = FakeInput,
	holdFor = holdFor,
	runUntil = runUntil,
}
