-- The actions the builder's context menu offers for a selection (pure):
-- an ordered list of labels, so a menu or a panel can show the same list.
-- Only the actions that apply are listed; the screen maps each label to
-- its handler.
local Scene = require("src.game.builder.scene")
local Builtins = require("src.game.designs.builtins")

local Actions = {}

-- The labels of the "Make 3D" submenu for a shape, and for a path.
Actions.MAKE_3D = "Make 3D"
Actions.BACK = "◂ Back"
Actions.SHAPE_MAKE = { "Extrude", "Lathe", "Sweep along path…", Actions.BACK }
Actions.PATH_MAKE = { "Sweep a shape along this…", Actions.BACK }

local OPERATIONS = { extrude = true, lathe = true, sweep = true }

local function isRolePrefab(name)
	for _, role in ipairs(Builtins.PREFABS) do
		if role == name then
			return true
		end
	end
	return false
end

-- The labels for `selection` (node ids) in `scene`. a `locked` script
-- gets no Make 3D (its other edits are refused with a message). `library` is unused for now.
function Actions.of(scene, selection, _library, locked)
	local nodes = {}
	for _, id in ipairs(selection or {}) do
		local node, parent = Scene.find(scene, id)
		if node then
			nodes[#nodes + 1] = { node = node, parent = parent }
		end
	end
	local only = #nodes == 1 and nodes[1] or nil
	local isRoot = only and only.node == scene.root
	local prefab = only and only.node.kind == "prefab" and only.node or nil
	local out = {}
	if #nodes == 0 or isRoot then
		return { "Rename", "Export as prefab", "Reset to default" }
	end
	if only then
		out[#out + 1] = "Rename"
	end
	out[#out + 1] = "Delete"
	out[#out + 1] = "Duplicate"
	out[#out + 1] = "Group"
	local bare = only and not (only.parent and OPERATIONS[only.parent.kind])
	if bare and not locked and (only.node.kind == "shape" or only.node.kind == "path") then
		out[#out + 1] = Actions.MAKE_3D
	end
	out[#out + 1] = "Export as prefab"
	if prefab then
		if not isRolePrefab(prefab.prefab) then
			out[#out + 1] = "Unlink"
		end
		out[#out + 1] = "Edit prefab"
	end
	out[#out + 1] = "Reset to default"
	return out
end

-- Whether the Material and Colour sections show for `selection`: any
-- selected node has volume (Scene.hasVolume).
function Actions.showPaint(scene, selection)
	for _, id in ipairs(selection or {}) do
		local node = Scene.find(scene, id)
		if node and Scene.hasVolume(node) then
			return true
		end
	end
	return false
end

-- The submenu "Make 3D" opens for node kind `kind`.
function Actions.make3d(kind)
	return kind == "path" and Actions.PATH_MAKE or Actions.SHAPE_MAKE
end

return Actions
