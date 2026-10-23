-- The Insert tool's game side (docs/CONTEXT.md "Node", "Prefab", "Role
-- prefab", "Work plane"): what it offers and the node each item places on
-- the work plane (src/game/builder/work_plane.lua finds the point). Pure;
-- plain LuaJIT.
--
--   item = { label, kind = "box" | "sphere" | ... }   a primitive
--        | { label, prefab = "<name>" }               a library prefab
local Api = require("src.game.script.api")

local Insert = {}

Insert.PRIMITIVES = {
	{ label = "Box", kind = "box" },
	{ label = "Sphere", kind = "sphere" },
	{ label = "Cylinder", kind = "cylinder" },
	{ label = "Cone", kind = "cone" },
	{ label = "Wedge", kind = "wedge" },
}

-- What the Insert tool offers from design library `library` ({ designs,
-- prefabs }): every primitive, then every prefab, role prefabs included,
-- by name.
function Insert.items(library)
	local items = {}
	for i, item in ipairs(Insert.PRIMITIVES) do
		items[i] = item
	end
	local names = {}
	for name in pairs(library.prefabs) do
		names[#names + 1] = name
	end
	table.sort(names)
	for _, name in ipairs(names) do
		items[#items + 1] = { label = name, prefab = name }
	end
	return items
end

-- A primitive node at its defaults, built by the design API itself so the
-- defaults have one source.
local function primitive(kind)
	local functions = Api.new()
	return functions[kind]({})
end

-- The node `item` places with its origin on design-space `point` { x, y, z
-- } (tiles). A sphere, centred on its origin, rises by its radius to rest
-- on the plane. The node has no id; Scene.insert gives it one.
function Insert.node(item, point)
	local node
	if item.prefab then
		node = { kind = "prefab", prefab = item.prefab, children = {} }
	else
		node = primitive(item.kind)
		node.id = nil
	end
	local lift = node.kind == "sphere" and node.radius or 0
	node.transform = { move = { point[1], point[2], point[3] + lift } }
	return node
end

return Insert
