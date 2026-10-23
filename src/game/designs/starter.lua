-- The built-in starting storage facility (docs/CONTEXT.md "Storage
-- facility"): the Lua design content/designs/storage_facility.lua, placed
-- free at the world centre in a new game (Session.newGame). Its depot,
-- storage and ports come from role prefabs. Pure -- no `love.*`, no file
-- reads: the script texts come in a library (src/game/designs/library.lua),
-- where a saved design of the same name shadows the built-in.
local Compile = require("src.game.buildings.compile")

local Starter = {}

-- The design's name (src/game/designs/builtins.lua).
Starter.NAME = "storage_facility"

-- The starter's blueprint, compiled from `library`. Raises when the design
-- doesn't compile: the game can't start without it.
function Starter.blueprint(library, config)
	local text = assert(library.designs[Starter.NAME], "no design " .. Starter.NAME)
	return assert(Compile.design(text, Starter.NAME, library, config))
end

return Starter
