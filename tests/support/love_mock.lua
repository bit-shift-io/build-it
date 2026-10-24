-- Minimal love.* mock for the integration tier: enough of love.keyboard,
-- love.joystick, love.timer, love.graphics and love.filesystem for the app's
-- input path to run
-- without a window. Nothing in src/game or src/core touches `love.*`
-- (docs/ARCHITECTURE.md "Layers"); this exists for src/app code that the
-- harness drives. Extend it when a test reaches a new love.* call.
local LoveMock = {}

local function quote(path)
	return "'" .. path:gsub("'", "'\\''") .. "'"
end

local function isDirectory(path)
	return os.execute("test -d " .. quote(path)) == 0
end

-- love.filesystem over a real directory standing in for the save directory,
-- so code that renames real files under getSaveDirectory() (atomic writes)
-- runs for real. The directory is made on the first write, so tests that
-- never write leave nothing behind.
local function newFilesystem(saveDir)
	local root = saveDir
	local function base()
		if not root then
			root = os.tmpname()
			os.remove(root)
		end
		os.execute("mkdir -p " .. quote(root))
		return root
	end
	local function real(path)
		return (root or "/nonexistent-save-dir") .. "/" .. path
	end

	local fs = {}
	function fs.getSaveDirectory()
		return base()
	end
	function fs.createDirectory(path)
		return os.execute("mkdir -p " .. quote(base() .. "/" .. path)) == 0
	end
	function fs.write(path, data)
		local file, err = io.open(base() .. "/" .. path, "wb")
		if not file then
			return false, err
		end
		file:write(data)
		file:close()
		return true
	end
	function fs.read(path)
		-- Like LÖVE, a path missing from the save directory is read from the
		-- game's own files (the repo, the tests' working directory).
		local file = io.open(real(path), "rb") or io.open(path, "rb")
		if not file then
			return nil, "could not open " .. path
		end
		local text = file:read("*a")
		file:close()
		return text, #text
	end
	function fs.getInfo(path)
		if isDirectory(real(path)) then
			return { type = "directory" }
		end
		local file = io.open(real(path), "rb")
		if not file then
			return nil
		end
		local size = file:seek("end")
		file:close()
		-- Seconds since the epoch, as LÖVE gives it (BSD stat, else GNU).
		local stat = io.popen("stat -f %m " .. quote(real(path)) .. " 2>/dev/null || stat -c %Y " .. quote(real(path)))
		local modtime = tonumber(stat:read("*l"))
		stat:close()
		return { type = "file", size = size, modtime = modtime }
	end
	function fs.getDirectoryItems(path)
		local items = {}
		if not isDirectory(real(path)) then
			return items
		end
		local ls = io.popen("ls -1A " .. quote(real(path)))
		for name in ls:lines() do
			items[#items + 1] = name
		end
		ls:close()
		return items
	end
	function fs.remove(path)
		return os.remove(real(path)) ~= nil
	end
	return fs
end

-- Builds one fresh mock (own keyboard/joystick state) per test so tests
-- don't leak input state between each other. opts.saveDir reuses a real
-- save directory (a previous mock's love.filesystem.getSaveDirectory()), so
-- a test can "relaunch" over the same files; otherwise each mock gets its
-- own temporary one.
function LoveMock.new(opts)
	opts = opts or {}
	local state = {
		keysDown = {},
		joysticks = {},
	}

	local love = {}

	love.keyboard = {
		isDown = function(key)
			return state.keysDown[key] == true
		end,
		-- Off until the app turns it on, as under SDL3 (LÖVE 12).
		setTextInput = function(enabled)
			state.textInput = enabled
		end,
		hasTextInput = function()
			return state.textInput == true
		end,
		setKeyRepeat = function(enabled)
			state.keyRepeat = enabled
		end,
	}

	-- The clipboard, and every URL openURL was asked for (state.opened);
	-- opening succeeds unless state.openFails.
	state.clipboard, state.opened = "", {}
	love.system = {
		getClipboardText = function()
			return state.clipboard
		end,
		setClipboardText = function(text)
			state.clipboard = text
		end,
		openURL = function(url)
			state.opened[#state.opened + 1] = url
			return not state.openFails
		end,
	}

	love.filesystem = newFilesystem(opts.saveDir)

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
