-- The design library (docs/CONTEXT.md "Design library"): every design and
-- prefab script by name. Pure -- no `love.*`; reading and writing the files
-- is src/app/design_store.lua's job, and the built-ins come from
-- src/game/designs/builtins.lua.
--
--   library = { designs = { [name] = <script text> },
--               prefabs = { [name] = <script text> } }
-- the shape src/game/script/resolve.lua looks prefabs up in.
local Compile = require("src.game.buildings.compile")

local Library = {}

local KINDS = { "designs", "prefabs" }

function Library.new()
	return { designs = {}, prefabs = {} }
end

-- The library of `builtins` with `saved` over it: a saved script shadows
-- the built-in of the same kind and name. Neither table is changed.
function Library.merge(builtins, saved)
	local lib = Library.new()
	for _, kind in ipairs(KINDS) do
		for _, source in ipairs({ builtins, saved }) do
			for name, text in pairs(source[kind] or {}) do
				lib[kind][name] = text
			end
		end
	end
	return lib
end

-- The designs the building picker offers, by name: every design that
-- compiles (src/game/buildings/compile.lua) to a blueprint with at least
-- one function role and no other problem (Compile.problems).
--   { { name, blueprint }, ... }
-- A design that fails to compile is left out.
function Library.placeable(lib, config)
	local names = {}
	for name in pairs(lib.designs) do
		names[#names + 1] = name
	end
	table.sort(names)
	local out = {}
	for _, name in ipairs(names) do
		local blueprint = Compile.design(lib.designs[name], name, lib, config)
		if blueprint and #Compile.problems(blueprint, config) == 0 then
			out[#out + 1] = { name = name, blueprint = blueprint }
		end
	end
	return out
end

return Library
