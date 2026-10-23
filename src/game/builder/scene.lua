-- The builder's scene (docs/CONTEXT.md "Builder", "Node"): the node tree of
-- the design script being edited (src/game/script/api.lua, before prefabs
-- resolve) and which of its nodes are selected. Pure; plain LuaJIT.
--
--   { root = <node>, selection = { <id>, ... } }   selection in click order
--
-- Every node has an id unique in the tree; Scene.new gives any node
-- without one (or with a taken one) a fresh id, kind and a number:
-- "box1". A prefab instance's own tree is not the scene's: it is never
-- walked here.
local Shape2d = require("src.game.geometry.shape2d")
local Lathe = require("src.game.geometry.lathe")
local Api = require("src.game.script.api")

local Scene = {}

-- `node` and every node under it, parents first, children of prefab
-- instances skipped: fn(node, depth, parent) for each.
local function walk(node, fn, depth, parent)
	fn(node, depth or 0, parent)
	if node.kind ~= "prefab" then
		for _, child in ipairs(node.children or {}) do
			walk(child, fn, (depth or 0) + 1, node)
		end
	end
end

-- The ids in use under `root`: { [id] = true }.
local function idsIn(root)
	local used = {}
	walk(root, function(node)
		if node.id then
			used[node.id] = true
		end
	end)
	return used
end

-- The first of kind1, kind2, ... not in `used`, marked used.
local function freshId(kind, used)
	local n = 1
	while used[kind .. n] do
		n = n + 1
	end
	used[kind .. n] = true
	return kind .. n
end

-- Gives every node under `root` without an id, or with one an earlier
-- node already holds, a fresh one. The same tree always gets the same ids.
function Scene.ensureIds(root)
	local used, seen = idsIn(root), {}
	walk(root, function(node)
		if not node.id or seen[node.id] then
			node.id = freshId(node.kind, used)
		end
		seen[node.id] = true
	end)
	return root
end

-- A scene over node tree `root` (taken, not copied), nothing selected.
function Scene.new(root)
	return { root = Scene.ensureIds(root), selection = {} }
end

-- The tree panel's rows: { { node, depth }, ... } in tree order.
function Scene.rows(scene)
	local rows = {}
	walk(scene.root, function(node, depth)
		rows[#rows + 1] = { node = node, depth = depth }
	end)
	return rows
end

function Scene.isSelected(scene, id)
	for _, selected in ipairs(scene.selection) do
		if selected == id then
			return true
		end
	end
	return false
end

-- A click on node `id` (nil: on nothing). It becomes the selection, or,
-- when `add` (Ctrl held), joins it or leaves it if already in it.
function Scene.select(scene, id, add)
	if id == nil and add then
		return
	end
	if not add then
		scene.selection = { id }
		return
	end
	for i, selected in ipairs(scene.selection) do
		if selected == id then
			table.remove(scene.selection, i)
			return
		end
	end
	table.insert(scene.selection, id)
end

-- Node `id`, its parent and its index among the parent's children; nil
-- when no node has that id.
function Scene.find(scene, id)
	local found, parent
	walk(scene.root, function(node, _, p)
		if node.id == id and not found then
			found, parent = node, p
		end
	end)
	if not found then
		return nil
	end
	for i, child in ipairs(parent and parent.children or {}) do
		if child == found then
			return found, parent, i
		end
	end
	return found
end

-- Names node `id` `name`; an empty name clears it. True when it took.
function Scene.rename(scene, id, name)
	local node = Scene.find(scene, id)
	if not node then
		return false, "no node " .. tostring(id)
	end
	node.name = name ~= "" and name or nil
	return true
end

-- The selected nodes that still exist, with their parents and indices:
-- { { node, parent, index }, ... }; nil and why when the root is one.
local function selectedNodes(scene)
	local out = {}
	for _, id in ipairs(scene.selection) do
		local node, parent, index = Scene.find(scene, id)
		if node == scene.root then
			return nil, "the root can't be"
		end
		if parent and (parent.kind == "extrude" or parent.kind == "sweep" or parent.kind == "lathe") then
			local article = parent.kind == "extrude" and "an " or "a "
			return nil, "a " .. node.kind .. " inside " .. article .. parent.kind .. " can't be"
		end
		if node then
			out[#out + 1] = { node = node, parent = parent, index = index }
		end
	end
	return out
end

-- Removes the selected nodes, children and all. True when it took; false
-- and why when nothing is selected or the root is.
function Scene.delete(scene)
	local nodes, reason = selectedNodes(scene)
	if not nodes then
		return false, reason .. " deleted"
	end
	if #nodes == 0 then
		return false, "nothing selected"
	end
	for _, s in ipairs(nodes) do
		for i, child in ipairs(s.parent.children) do
			if child == s.node then
				table.remove(s.parent.children, i)
				break
			end
		end
	end
	scene.selection = {}
	return true
end

local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		out[k] = deepCopy(x)
	end
	return out
end

Scene.copy = deepCopy

-- Copies each selected node, children and all, right after it, every
-- copied node with a fresh id; the copies become the selection. True when
-- it took; false and why otherwise.
function Scene.duplicate(scene)
	local nodes, reason = selectedNodes(scene)
	if not nodes then
		return false, reason .. " duplicated"
	end
	if #nodes == 0 then
		return false, "nothing selected"
	end
	local used, copies = idsIn(scene.root), {}
	for _, s in ipairs(nodes) do
		local copy = deepCopy(s.node)
		walk(copy, function(node)
			node.id = freshId(node.kind, used)
		end)
		for i, child in ipairs(s.parent.children) do
			if child == s.node then
				table.insert(s.parent.children, i + 1, copy)
				break
			end
		end
		copies[#copies + 1] = copy.id
	end
	scene.selection = copies
	return true
end

-- Wraps the selected nodes, which must share a parent, in a new group
-- named "Group" where the first of them stood, keeping their order; the
-- group becomes the selection. True when it took; false and why otherwise.
function Scene.group(scene)
	local nodes, reason = selectedNodes(scene)
	if not nodes then
		return false, reason .. " grouped"
	end
	if #nodes == 0 then
		return false, "nothing selected"
	end
	local parent = nodes[1].parent
	for _, s in ipairs(nodes) do
		if s.parent ~= parent then
			return false, "only nodes in the same group can be grouped"
		end
	end
	table.sort(nodes, function(a, b)
		return a.index < b.index
	end)
	local group = { kind = "group", id = freshId("group", idsIn(scene.root)), name = "Group", transform = {}, children = {} }
	for i = #nodes, 1, -1 do
		table.remove(parent.children, nodes[i].index)
	end
	for i, s in ipairs(nodes) do
		group.children[i] = s.node
	end
	table.insert(parent.children, nodes[1].index, group)
	scene.selection = { group.id }
	return true
end

-- Wraps the one selected shape in a new extrude node, one tile high, where
-- it stood; the extrude becomes the selection. True when it took; false and
-- why otherwise.
function Scene.extrude(scene)
	local nodes, reason = selectedNodes(scene)
	if not nodes then
		return false, reason .. " extruded"
	end
	local only = nodes[1]
	if #nodes ~= 1 or only.node.kind ~= "shape" then
		return false, "select one shape to extrude"
	end
	if not Shape2d.outline(only.node.points) then
		return false, "the shape isn't closed"
	end
	local extrude = {
		kind = "extrude",
		id = freshId("extrude", idsIn(scene.root)),
		height = 1,
		transform = {},
		children = { only.node },
	}
	only.parent.children[only.index] = extrude
	scene.selection = { extrude.id }
	return true
end

-- Wraps the one selected shape in a new lathe node, a full turn about its
-- plane's v axis, where it stood; the lathe becomes the selection. True
-- when it took; false and why otherwise.
function Scene.lathe(scene)
	local nodes, reason = selectedNodes(scene)
	if not nodes then
		return false, reason .. " lathed"
	end
	local only = nodes[1]
	if #nodes ~= 1 or only.node.kind ~= "shape" then
		return false, "select one shape to lathe"
	end
	local outline = Shape2d.outline(only.node.points)
	if not outline then
		return false, "the shape isn't closed"
	end
	if not Lathe.valid(outline) then
		return false, "the shape crosses the lathe axis"
	end
	local lathe = {
		kind = "lathe",
		id = freshId("lathe", idsIn(scene.root)),
		angle = 360,
		segments = Api.SEGMENTS.default,
		transform = {},
		children = { only.node },
	}
	only.parent.children[only.index] = lathe
	scene.selection = { lathe.id }
	return true
end

-- Puts the one selected shape and path `pathId` in a new sweep node, no
-- twist and at full scale, where the path stood (the shape leaves its
-- place); the sweep becomes the selection. True when it took; false and
-- why otherwise.
function Scene.sweep(scene, pathId)
	local nodes, reason = selectedNodes(scene)
	if not nodes then
		return false, reason .. " swept"
	end
	local only = nodes[1]
	if #nodes ~= 1 or only.node.kind ~= "shape" then
		return false, "select one shape to sweep"
	end
	if not Shape2d.outline(only.node.points) then
		return false, "the shape isn't closed"
	end
	local path, parent = Scene.find(scene, pathId)
	if not path or path.kind ~= "path" then
		return false, "sweep along a path"
	end
	if parent.kind == "extrude" or parent.kind == "sweep" then
		return false, "that path is already in a sweep"
	end
	local sweep = {
		kind = "sweep",
		id = freshId("sweep", idsIn(scene.root)),
		twist = 0,
		startScale = 1,
		endScale = 1,
		transform = {},
		children = { only.node, path },
	}
	table.remove(only.parent.children, only.index)
	for i, child in ipairs(parent.children) do
		if child == path then
			parent.children[i] = sweep
		end
	end
	scene.selection = { sweep.id }
	return true
end

-- Makes every selected node, the root included, of `material` (Api's node
-- material: { name, variant, scale, rotation }), each its own copy with
-- every part filled in. True when it took; false and why otherwise.
function Scene.setMaterial(scene, material)
	local checked, why = Api.material(material)
	if not checked then
		return false, why
	end
	local nodes = {}
	for _, id in ipairs(scene.selection) do
		nodes[#nodes + 1] = Scene.find(scene, id)
	end
	if #nodes == 0 then
		return false, "nothing selected"
	end
	for _, node in ipairs(nodes) do
		node.material = deepCopy(checked)
	end
	return true
end

-- The material node `id` is made of: its own, else that of the nearest
-- node above it with one; nil when none does.
function Scene.material(scene, id)
	local found
	local function search(node, inherited)
		local material = node.material or inherited
		if node.id == id then
			found = material
			return true
		end
		if node.kind ~= "prefab" then
			for _, child in ipairs(node.children or {}) do
				if search(child, material) then
					return true
				end
			end
		end
	end
	search(scene.root, nil)
	return found
end

-- Adds `node` (taken, not copied) as the root group's last child with a
-- fresh id (its prefab's name or its kind, and a number: "saw1"), and
-- selects it. A root that is not a group is first wrapped, with the new
-- node, in a new root group. True: it always takes.
function Scene.insert(scene, node)
	local used = idsIn(scene.root)
	node.id = freshId(node.prefab or node.kind, used)
	if scene.root.kind ~= "group" then
		local id = used.root and freshId("group", used) or "root"
		scene.root = { kind = "group", id = id, transform = {}, children = { scene.root } }
	end
	table.insert(scene.root.children, node)
	scene.selection = { node.id }
	return true
end

-- What the tree panel calls `node`: its name, else its id.
function Scene.label(node)
	return node.name or node.id
end

return Scene
