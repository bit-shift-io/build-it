-- The design library (docs/CONTEXT.md "Design library"): every design and
-- prefab script by name. Pure -- no `love.*`; reading and writing the files
-- is src/app/design_store.lua's job, and the built-ins come from
-- src/game/designs/builtins.lua.
--
--   library = { designs = { [name] = <script text> },
--               prefabs = { [name] = <script text> } }
-- the shape src/game/script/resolve.lua looks prefabs up in.
local Compile = require("src.game.buildings.compile")
local Builtins = require("src.game.designs.builtins")

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

-- Whether `name` of `kind` ("designs" | "prefabs") is one the game ships
-- (src/game/designs/builtins.lua). A saved script of that name shadows it.
function Library.builtin(kind, name)
	for _, shipped in ipairs(kind == "designs" and Builtins.DESIGNS or Builtins.prefabNames()) do
		if shipped == name then
			return true
		end
	end
	return false
end

-- Reset to default: the saved scripts `saved` ({ designs, prefabs }, the
-- save directory's) without the shadow of built-in `name` of `kind`, so
-- the built-in shows again. `saved` is not changed; the caller deletes the
-- file. Nil and why when `name` is no built-in or has no shadow.
function Library.reset(saved, kind, name)
	if not Library.builtin(kind, name) then
		return nil, "only a built-in can be reset to default"
	end
	if not (saved[kind] or {})[name] then
		return nil, name .. " is already the default"
	end
	local out = Library.merge(Library.new(), saved)
	out[kind][name] = nil
	return out
end

-- Whether script `name` of `kind` may be deleted or renamed: true, or
-- false and why. Built-ins can't be.
function Library.removable(kind, name)
	if Library.builtin(kind, name) then
		return false, "built-ins can't be deleted or renamed"
	end
	return true
end

-- A copy of library `lib` ({ designs, prefabs }).
local function copy(lib)
	return Library.merge(Library.new(), lib)
end

-- Whether `name` is a script name (a plain file name: letters, digits, _
-- and -, src/app/design_store.lua) no script of `kind` in `lib` has: true,
-- or false and why.
local function free(lib, kind, name)
	if type(name) ~= "string" or not name:match("^[%w_%-]+$") then
		return false, "a name is letters, digits, _ and -"
	end
	if lib[kind][name] then
		return false, "a " .. kind:sub(1, -2) .. " called " .. name .. " already exists"
	end
	return true
end

-- Library `lib` with script `from` of `kind` renamed `to`: its text moves
-- and nothing else changes, so a script that places it by its old name
-- now fails to load, naming it (Resolve.design). Nil and why when `from`
-- is a built-in or missing, or `to` is a bad or taken name. `lib` is not
-- changed.
function Library.rename(lib, kind, from, to)
	local ok, why = Library.removable(kind, from)
	if not ok then
		return nil, why
	end
	if not lib[kind][from] then
		return nil, "no " .. kind:sub(1, -2) .. " called " .. tostring(from)
	end
	ok, why = free(lib, kind, to)
	if not ok then
		return nil, why
	end
	local out = copy(lib)
	out[kind][to] = out[kind][from]
	out[kind][from] = nil
	return out
end

-- What the library manager lists for `kind` in `lib`: { { name, builtin
-- }, ... } sorted by name.
function Library.entries(lib, kind)
	local out = {}
	for name in pairs(lib[kind]) do
		out[#out + 1] = { name = name, builtin = Library.builtin(kind, name) }
	end
	table.sort(out, function(a, b)
		return a.name < b.name
	end)
	return out
end

-- Library `lib` without script `name` of `kind`; a script placing it now
-- fails to load, naming it. Nil and why when it is a built-in (Reset to
-- default is Library.reset) or missing. `lib` is not changed.
function Library.delete(lib, kind, name)
	local ok, why = Library.removable(kind, name)
	if not ok then
		return nil, why
	end
	if not lib[kind][name] then
		return nil, "no " .. kind:sub(1, -2) .. " called " .. tostring(name)
	end
	local out = copy(lib)
	out[kind][name] = nil
	return out
end

-- The name Duplicate offers for a copy of `name` of `kind` in `lib`:
-- "<name>_copy", else "<name>_copy2", "<name>_copy3", ... whichever is
-- first free.
function Library.copyName(lib, kind, name)
	return Library.freeName(lib, kind, name .. "_copy")
end

-- `base` when no script of `kind` in `lib` has it, else the first free of
-- "<base>2", "<base>3", ...
function Library.freeName(lib, kind, base)
	local name, n = base, 1
	while lib[kind][name] do
		n = n + 1
		name = base .. n
	end
	return name
end

-- Library `lib` with a copy of script `from` of `kind` (a built-in too)
-- as `to`. Nil and why when `from` is missing or `to` is a bad or taken
-- name. `lib` is not changed.
function Library.duplicate(lib, kind, from, to)
	if not lib[kind][from] then
		return nil, "no " .. kind:sub(1, -2) .. " called " .. tostring(from)
	end
	local ok, why = free(lib, kind, to)
	if not ok then
		return nil, why
	end
	local out = copy(lib)
	out[kind][to] = out[kind][from]
	return out
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
