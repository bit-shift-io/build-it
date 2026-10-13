-- The design library on disk (docs/CONTEXT.md "Design library"): one file
-- per design, all its versions, under `dir` in the save directory
-- (config.designs.dir), shared by every world. Files are
-- <id>.design, in src/game/designs/codec.lua's format.
--
-- Writes are atomic: the text goes to <id>.design.tmp, then os.rename swaps
-- it in, so a crash mid-save leaves either the old file or the new one,
-- never half of one. LÖVE 12's love.filesystem has no rename
-- (docs/memory/love-12-no-filesystem-rename.md), so the rename runs on the
-- real paths under love.filesystem.getSaveDirectory().
local Codec = require("src.game.designs.codec")
local Library = require("src.game.designs.library")

local DesignStore = {}

local SUFFIX = ".design"

-- The library in `dir`, and its problems: one { name, reason } per file that
-- could not be read. A missing directory is an empty library.
function DesignStore.load(dir)
	local files = {}
	for _, name in ipairs(love.filesystem.getDirectoryItems(dir)) do
		if name:sub(-#SUFFIX) == SUFFIX then
			local text = love.filesystem.read(dir .. "/" .. name)
			table.insert(files, { name = name, text = text })
		end
	end
	table.sort(files, function(a, b)
		return a.name < b.name
	end)
	return Library.fromFiles(files)
end

-- Writes `design` (all its versions) to its file in `dir`. Returns true, or
-- nil and why it failed; on failure the previous file stays as it was.
function DesignStore.write(dir, design)
	local path = dir .. "/" .. design.id .. SUFFIX
	local tmp = path .. ".tmp"
	love.filesystem.createDirectory(dir)
	local ok, err = love.filesystem.write(tmp, Codec.encode(design))
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
