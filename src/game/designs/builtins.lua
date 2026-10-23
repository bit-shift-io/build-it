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

Builtins.DESIGNS = { "storage_facility" }

-- The path of built-in `name` of `kind` ("designs" | "prefabs").
function Builtins.path(kind, name)
	return Builtins.DIR .. "/" .. kind .. "/" .. name .. ".lua"
end

-- Every built-in's text through `read(path)` (text, or nil and why not):
-- the library, or nil and a message naming the file that failed.
function Builtins.load(read)
	local library = { designs = {}, prefabs = {} }
	for kind, names in pairs({ designs = Builtins.DESIGNS, prefabs = Builtins.PREFABS }) do
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
