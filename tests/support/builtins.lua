-- The built-in design library (src/game/designs/builtins.lua) read from
-- the repo with plain file reads, for tests that run without LÖVE.
local Builtins = require("src.game.designs.builtins")

local function read(path)
	local file, err = io.open(path, "rb")
	if not file then
		return nil, err
	end
	local text = file:read("*a")
	file:close()
	return text
end

return assert(Builtins.load(read))
