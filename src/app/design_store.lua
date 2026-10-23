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

-- A file changed this many seconds before `now`, or later, may change again
-- within its modtime's second: its stamp holds its text too.
local RECENT = 2

-- A cheap fingerprint of every saved script, for hot reload: it changes
-- when any file is added, removed or changed. Each file counts by its
-- modtime and size (love.filesystem.getInfo); modtimes are whole seconds,
-- so a file changed in the last RECENT seconds (of `now`, os.time() unless
-- given) counts by its text as well, catching a second same-size edit
-- within one second.
function DesignStore.stamp(cfg, now)
	now = now or os.time()
	local parts = {}
	for _, dir in ipairs({ cfg.dir, cfg.prefabDir }) do
		local files = love.filesystem.getDirectoryItems(dir)
		table.sort(files)
		for _, file in ipairs(files) do
			if file:sub(-#SUFFIX) == SUFFIX then
				local path = dir .. "/" .. file
				local info = love.filesystem.getInfo(path) or {}
				local part = path .. " " .. tostring(info.modtime) .. " " .. tostring(info.size)
				if not info.modtime or info.modtime >= now - RECENT then
					part = part .. "\n" .. tostring(love.filesystem.read(path))
				end
				parts[#parts + 1] = part
			end
		end
	end
	return table.concat(parts, "\n")
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

-- Renames the saved script `from` of `kind` to `to`, moving its file in
-- one os.rename, so it is never in both places or neither. True, or nil
-- and why; a script already called `to` is left alone.
function DesignStore.rename(cfg, kind, from, to)
	for _, name in ipairs({ from, to }) do
		if type(name) ~= "string" or not name:match("^[%w_%-]+$") then
			return nil, "bad name " .. tostring(name)
		end
	end
	local dir = folder(cfg, kind)
	local source, target = dir .. "/" .. from .. SUFFIX, dir .. "/" .. to .. SUFFIX
	if not love.filesystem.getInfo(source) then
		return nil, "no file " .. source
	end
	if love.filesystem.getInfo(target) then
		return nil, target .. " already exists"
	end
	local root = love.filesystem.getSaveDirectory() .. "/"
	local ok, err = os.rename(root .. source, root .. target)
	if not ok then
		return nil, err or "could not rename " .. source
	end
	return true
end

-- Deletes the saved script `name` of `kind`: for a built-in, Reset to
-- default (src/game/designs/library.lua Library.reset). True, or nil and
-- why.
function DesignStore.remove(cfg, kind, name)
	if type(name) ~= "string" or not name:match("^[%w_%-]+$") then
		return nil, "bad name " .. tostring(name)
	end
	local path = folder(cfg, kind) .. "/" .. name .. SUFFIX
	if not love.filesystem.remove(path) then
		return nil, "could not delete " .. path
	end
	return true
end

return DesignStore
