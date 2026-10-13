-- Minimal love.* mock for the integration tier: enough of love.keyboard,
-- love.joystick, love.timer and love.graphics for the app's input path to run
-- without a window. Nothing in src/game or src/core touches `love.*`
-- (docs/ARCHITECTURE.md "Layers"); this exists for src/app code that the
-- harness drives. Extend it when a test reaches a new love.* call.
local LoveMock = {}

-- Builds one fresh mock (own keyboard/joystick state) per test so tests
-- don't leak input state between each other.
function LoveMock.new()
	local state = {
		keysDown = {},
		joysticks = {},
	}

	local love = {}

	love.keyboard = {
		isDown = function(key)
			return state.keysDown[key] == true
		end,
	}

	love.joystick = {
		getJoysticks = function()
			return state.joysticks
		end,
	}

	love.timer = {
		_getTime = 0,
		getDelta = function()
			return 1 / 60
		end,
		getTime = function()
			love.timer._getTime = love.timer._getTime + 1 / 60
			return love.timer._getTime
		end,
		sleep = function() end,
	}

	love.getVersion = function()
		return 12, 0, 0
	end

	local noop = function() end
	love.graphics = {
		getWidth = function()
			return 1280
		end,
		getHeight = function()
			return 720
		end,
		getDimensions = function()
			return 1280, 720
		end,
		setColor = noop,
		setBackgroundColor = noop,
		push = noop,
		pop = noop,
		translate = noop,
		scale = noop,
		line = noop,
		rectangle = noop,
		setLineWidth = noop,
	}

	love._state = state
	return love
end

return LoveMock
