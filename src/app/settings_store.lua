-- The player's settings file: config.settings.file in the save directory, in
-- src/game/settings.lua's format. Written atomically like
-- src/app/save_store.lua (<file>.tmp, then os.rename; LÖVE 12 has no
-- love.filesystem.rename). A missing or corrupt file reads as the defaults.
local Settings = require("src.game.settings")

local SettingsStore = {}

function SettingsStore.load(config)
	return Settings.decode(config, love.filesystem.read(config.settings.file))
end

-- Returns true, or nil and why it failed.
function SettingsStore.write(config, settings)
	local path = config.settings.file
	local tmp = path .. ".tmp"
	local ok, err = love.filesystem.write(tmp, Settings.encode(settings))
	if not ok then
		return nil, err or "could not write " .. tmp
	end
	local root = love.filesystem.getSaveDirectory() .. "/"
	ok, err = os.rename(root .. tmp, root .. path)
	if not ok then
		love.filesystem.remove(tmp)
		return nil, err or "could not replace " .. path
	end
	return true
end

return SettingsStore
