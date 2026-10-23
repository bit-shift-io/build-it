-- The design library on disk (docs/CONTEXT.md "Design library"): one Lua
-- design script per design under cfg.dir and per prefab under
-- cfg.prefabDir in the save directory (config.designs), shared by every
-- world. A file <name>.lua holds the script named <name>; anything else in
-- the folders (old brick .design files, *.tmp leftovers) is ignored.
--
-- Files are read as text only: scripts run through the sandbox
-- (src/game/script/sandbox.lua), never `load` or `dofile`.
--
-- Writes are atomic: the text goes to <name>.lua.tmp, then os.rename swaps
-- it in, so a crash mid-save leaves either the old file or the new one,
-- never half of one. LÖVE 12's love.filesystem has no rename
-- (docs/memory/love-12-no-filesystem-rename.md), so the rename runs on the
-- real paths under love.filesystem.getSaveDirectory().
local DesignStore = {}

local SUFFIX = ".lua"

-- The folder of `kind` ("designs" | "prefabs") in cfg.
local function folder(cfg, kind)
	return assert(({ designs = cfg.dir, prefabs = cfg.prefabDir })[kind], "unknown kind " .. tostring(kind))
end

-- { [name] = text } of every <name>.lua in `dir`; a missing folder is empty.
local function readAll(dir)
	local out = {}
	for _, file in ipairs(love.filesystem.getDirectoryItems(dir)) do
		local name = file:sub(-#SUFFIX) == SUFFIX and file:sub(1, -#SUFFIX - 1)
		if name and name ~= "" then
			out[name] = love.filesystem.read(dir .. "/" .. file)
		end
	end
	return out
end

-- The saved library, { designs = { [name] = text }, prefabs = { ... } },
-- before the built-ins (src/game/designs/library.lua Library.merge).
function DesignStore.load(cfg)
	return { designs = readAll(cfg.dir), prefabs = readAll(cfg.prefabDir) }
end

-- Writes script `text` as `name` of `kind` ("designs" | "prefabs").
-- Returns true, or nil and why it failed; on failure the previous file
-- stays as it was. A name is a plain file name: letters, digits, _ and -.
function DesignStore.write(cfg, kind, name, text)
	if type(name) ~= "string" or not name:match("^[%w_%-]+$") then
		return nil, "bad name " .. tostring(name)
	end
	local dir = folder(cfg, kind)
	local path = dir .. "/" .. name .. SUFFIX
	local tmp = path .. ".tmp"
	love.filesystem.createDirectory(dir)
	local ok, err = love.filesystem.write(tmp, text)
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

return DesignStore
