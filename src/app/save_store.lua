-- The world save slot on disk: one file, config.save.file in the save
-- directory, in src/game/save/codec.lua's format.
--
-- Writes are atomic like the design library's (src/app/design_store.lua):
-- the text goes to <file>.tmp, then os.rename swaps it in on the real
-- paths, since LÖVE 12's love.filesystem has no rename
-- (docs/memory/love-12-no-filesystem-rename.md).
local SaveCodec = require("src.game.save.codec")

local SaveStore = {}

-- Whether the slot holds a save.
function SaveStore.exists(config)
	local info = love.filesystem.getInfo(config.save.file)
	return info ~= nil and info.type == "file"
end

-- The saved session, tuned by `config`; or nil and why it could not load.
-- It needs no design library: buildings carry their blueprints.
function SaveStore.load(config)
	local text = love.filesystem.read(config.save.file)
	if not text then
		return nil, "no save"
	end
	return SaveCodec.decode(text, config)
end

-- Saves session `ctx` into the slot. Returns true, or nil and why it
-- failed; on failure the previous save stays as it was.
function SaveStore.write(ctx)
	local path = ctx.config.save.file
	local tmp = path .. ".tmp"
	local ok, err = love.filesystem.write(tmp, SaveCodec.encode(ctx))
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

return SaveStore
