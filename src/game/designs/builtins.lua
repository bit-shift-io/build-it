-- The built-in design scripts the game ships (docs/CONTEXT.md "Role
-- prefab", "Storage facility"), under content/. Pure: `game` never reads
-- files, so the caller hands in a reader -- love.filesystem.read in `app`,
-- a plain file read in tests.
--
--   library = { designs = { [name] = <script text> },
--               prefabs = { [name] = <script text> } }
-- the shape src/game/script/resolve.lua looks prefabs up in.
local Builtins = {}

Builtins.DIR = "content"

-- One role prefab per function brick ability, port kind and storage.
Builtins.PREFABS = {
	"saw",
	"pickaxe",
	"forager",
	"fishing",
	"hunter",
	"planter",
	"sawbench",
	"depot",
	"bed",
	"canteen",
	"input_port",
	"output_port",
	"storage",
}

-- Starter prefabs: parametric building parts, not roles. A saved prefab of
-- the same name shadows one, like any built-in.
Builtins.STARTER_PREFABS = {
	"wall",
	"window_frame",
	"door_frame",
	"gable_roof",
	"pitched_roof",
	"column",
	"arch",
	"chimney",
	"fence",
}

-- The starting storage facility, then the starter buildings.
Builtins.DESIGNS = {
	"storage_facility",
	"woodcutter",
	"quarry",
	"sawmill",
	"forager_hut",
	"fishing_hut",
	"hunter_lodge",
	"bedhouse",
	"canteen",
	"forester",
}

-- Every built-in prefab name: role prefabs, then starter prefabs.
function Builtins.prefabNames()
	local names = {}
	for _, list in ipairs({ Builtins.PREFABS, Builtins.STARTER_PREFABS }) do
		for _, name in ipairs(list) do
			names[#names + 1] = name
		end
	end
	return names
end

-- The path of built-in `name` of `kind` ("designs" | "prefabs").
function Builtins.path(kind, name)
	return Builtins.DIR .. "/" .. kind .. "/" .. name .. ".lua"
end

-- Every built-in's text through `read(path)` (text, or nil and why not):
-- the library, or nil and a message naming the file that failed.
function Builtins.load(read)
	local library = { designs = {}, prefabs = {} }
	for kind, names in pairs({ designs = Builtins.DESIGNS, prefabs = Builtins.prefabNames() }) do
		for _, name in ipairs(names) do
			local path = Builtins.path(kind, name)
			local text, err = read(path)
			if not text then
				return nil, "can't read " .. path .. ": " .. tostring(err)
			end
			library[kind][name] = text
		end
	end
	return library
end

return Builtins
