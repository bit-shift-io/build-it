-- Drives a fake keyboard/joystick state the way a human would: press/release
-- keys. Built on top of the *current* global `love` (the integration tier's
-- love_mock, or real LÖVE under the e2e tier) so construct a FakeInput only
-- once a `love` global exists (set `_G.love = LoveMock.new()` first in the
-- integration tier).
--
-- Shims love.keyboard.isDown and love.joystick.getJoysticks. Key taps and
-- mouse events go straight to the harnessed game's LÖVE-style callbacks
-- (tap, click, drag below).
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

-- One key press as LÖVE delivers it: a keypressed event, then one frame.
local function tap(game, key)
	game:keypressed(key)
	FrameStepper.step(game, 1)
end

-- Typed text as LÖVE delivers it: one textinput event per character, then
-- one frame. Only text: keys such as "backspace" or "return" are taps.
local function typeText(game, text)
	for char in text:gmatch("[^\128-\191][\128-\191]*") do
		game:textinput(char)
	end
	FrameStepper.step(game, 1)
end

-- Opens the building picker with the 1 key, types `query` into its search
-- and picks the first design matching it with Return.
local function pickDesign(game, query)
	tap(game, "1")
	typeText(game, query)
	tap(game, "return")
end

-- A mouse click at screen (x, y) with button (1 left, 2 right): the pointer
-- moves there, then presses and releases without moving.
local function click(game, button, x, y)
	game:mousemoved(x, y, 0, 0)
	game:mousepressed(x, y, button)
	game:mousereleased(x, y, button)
	FrameStepper.step(game, 1)
end

-- A drag with `button` held from (x1, y1) to (x2, y2), in a few moves.
local function drag(game, button, x1, y1, x2, y2)
	local MOVES = 4
	game:mousemoved(x1, y1, 0, 0)
	game:mousepressed(x1, y1, button)
	local x, y = x1, y1
	for i = 1, MOVES do
		local nx, ny = x1 + (x2 - x1) * i / MOVES, y1 + (y2 - y1) * i / MOVES
		game:mousemoved(nx, ny, nx - x, ny - y)
		x, y = nx, ny
		FrameStepper.step(game, 1)
	end
	game:mousereleased(x2, y2, button)
	FrameStepper.step(game, 1)
end

return {
	FakeInput = FakeInput,
	holdFor = holdFor,
	runUntil = runUntil,
	tap = tap,
	typeText = typeText,
	pickDesign = pickDesign,
	click = click,
	drag = drag,
}
