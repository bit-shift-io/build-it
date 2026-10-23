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
local Serialize = require("src.game.script.serialize")
local Resolve = require("src.game.script.resolve")
local Builtins = require("src.game.designs.builtins")

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

-- The tree panel's rows: { { node, depth, readOnly?, owner? }, ... } in
-- tree order. `expanded` (optional) maps a prefab instance's id to its
-- prefab's own tree (resolved, src/game/script/resolve.lua): those nodes
-- follow the instance's row, read-only, `owner` the instance's id.
function Scene.rows(scene, expanded)
	local rows = {}
	local function own(node, depth, owner)
		rows[#rows + 1] = { node = node, depth = depth, readOnly = true, owner = owner }
		for _, child in ipairs(node.children or {}) do
			own(child, depth + 1, owner)
		end
	end
	walk(scene.root, function(node, depth)
		rows[#rows + 1] = { node = node, depth = depth }
		local inside = node.kind == "prefab" and expanded and expanded[node.id]
		if inside then
			own(inside, depth + 1, node.id)
		end
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

-- Sets field `key` of every selected node, the root included, to its own
-- copy of `value`. True when it took; false and why otherwise.
local function setSelected(scene, key, value)
	local nodes = {}
	for _, id in ipairs(scene.selection) do
		nodes[#nodes + 1] = Scene.find(scene, id)
	end
	if #nodes == 0 then
		return false, "nothing selected"
	end
	for _, node in ipairs(nodes) do
		node[key] = deepCopy(value)
	end
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
	return setSelected(scene, "material", checked)
end

-- Paints every selected node, the root included, `color` (a node colour:
-- { r, g, b } or a team slot name, src/game/palette.lua), each its own
-- copy. True when it took; false and why otherwise.
function Scene.setColor(scene, color)
	local checked, why = Api.color(color)
	if not checked then
		return false, why
	end
	return setSelected(scene, "color", checked)
end

-- Field `key` of node `id`: its own, else that of the nearest node above
-- it with one; nil when none does.
local function inherited(scene, id, key)
	local found
	local function search(node, above)
		local value = node[key] or above
		if node.id == id then
			found = value
			return true
		end
		if node.kind ~= "prefab" then
			for _, child in ipairs(node.children or {}) do
				if search(child, value) then
					return true
				end
			end
		end
	end
	search(scene.root, nil)
	return found
end

-- The material node `id` is made of: its own, else that of the nearest
-- node above it with one; nil when none does.
function Scene.material(scene, id)
	return inherited(scene, id, "material")
end

-- The colour node `id` is painted: its own, else that of the nearest node
-- above it with one; nil when none does.
function Scene.color(scene, id)
	return inherited(scene, id, "color")
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

-- The nodes from the root down to node `id`, both included; nil when no
-- node has that id.
local function pathTo(scene, id)
	local function search(node, path)
		path[#path + 1] = node
		if node.id == id then
			return path
		end
		if node.kind ~= "prefab" then
			for _, child in ipairs(node.children or {}) do
				if search(child, path) then
					return path
				end
			end
		end
		path[#path] = nil
	end
	return search(scene.root, {})
end

-- Replaces the selected nodes with one instance of a new prefab called
-- `name` (docs/CONTEXT.md "Prefab") holding copies of them. The instance
-- goes in the nearest node holding them all, where the first of them
-- stood, and each copy keeps its place in the world and its look: it is
-- wrapped in a group per node between there and it, carrying that node's
-- transform, material and colour. `library` ({ prefabs }) is checked for a
-- prefab cycle the new one would make. Returns true and the new prefab's
-- script text, or false and why. Writing the file is the caller's job.
function Scene.export(scene, name, library)
	local nodes, reason = selectedNodes(scene)
	if not nodes then
		return false, reason .. " exported"
	end
	if #nodes == 0 then
		return false, "nothing selected"
	end
	local selected, paths = {}, {}
	for _, s in ipairs(nodes) do
		selected[s.node] = true
	end
	for _, s in ipairs(nodes) do
		local path = pathTo(scene, s.node.id)
		local inside = false
		for i = 1, #path - 1 do
			inside = inside or selected[path[i]]
		end
		if not inside then
			paths[#paths + 1] = path
		end
	end
	-- depth: how deep the nearest node holding every selected one is.
	local depth = #paths[1] - 1
	for _, path in ipairs(paths) do
		local i = 1
		while i <= depth and i < #path and path[i] == paths[1][i] do
			i = i + 1
		end
		depth = i - 1
	end
	local host = paths[1][depth]
	local copies = {}
	for i, path in ipairs(paths) do
		local copy = deepCopy(path[#path])
		for j = #path - 1, depth + 1, -1 do
			local above = path[j]
			copy = {
				kind = "group",
				id = above.id,
				name = above.name,
				transform = deepCopy(above.transform) or {},
				material = deepCopy(above.material),
				color = deepCopy(above.color),
				children = { copy },
			}
		end
		copies[i] = copy
	end
	local prefab = { kind = "group", id = "root", name = name, transform = {}, children = copies }
	local text = Serialize.tree(prefab)
	local check = { designs = library.designs, prefabs = {} }
	for k, v in pairs(library.prefabs) do
		check.prefabs[k] = v
	end
	check.prefabs[name] = text
	local ok, why = Resolve.design(text, name, check)
	if not ok and why:find("prefab cycle", 1, true) then
		return false, why
	end
	-- Where the instance goes: before the host's child leading to the first
	-- selected node in tree order.
	local first
	for index, child in ipairs(host.children) do
		for _, path in ipairs(paths) do
			if not first and path[depth + 1] == child then
				first = index
			end
		end
	end
	local instance = { kind = "prefab", prefab = name, id = freshId(name, idsIn(scene.root)), transform = {}, children = {} }
	table.insert(host.children, first, instance)
	for _, path in ipairs(paths) do
		local node, parent = path[#path], path[#path - 1]
		for i, child in ipairs(parent.children) do
			if child == node then
				table.remove(parent.children, i)
				break
			end
		end
	end
	scene.selection = { instance.id }
	return true, text
end

-- Overrides param `name` of prefab instance `id` with its own copy of
-- `value` (docs/CONTEXT.md "Param"). True when it took; false and why
-- otherwise. Whether the value fits the param is the prefab run's
-- concern (src/game/script/resolve.lua).
function Scene.setParam(scene, id, name, value)
	local node = Scene.find(scene, id)
	if not node or node.kind ~= "prefab" then
		return false, "only a prefab instance has params to override"
	end
	node.params = node.params or {}
	node.params[name] = deepCopy(value)
	return true
end

-- Whether `name` is a role prefab (docs/CONTEXT.md "Role prefab").
local function isRolePrefab(name)
	for _, role in ipairs(Builtins.PREFABS) do
		if role == name then
			return true
		end
	end
	return false
end

-- Replaces the one selected prefab instance with an editable copy of its
-- prefab (run with its overrides, src/game/script/resolve.lua, from
-- `library`): a group with the instance's id, name and transform holding
-- the prefab's tree, the instance's material and colour on every node of
-- it, any id the design already uses made fresh. The copy becomes the
-- selection. Role prefabs refuse. True when it took; false and why
-- otherwise.
function Scene.unlink(scene, library)
	local nodes, reason = selectedNodes(scene)
	if not nodes then
		return false, reason .. " unlinked"
	end
	local only = nodes[1]
	if #nodes ~= 1 or only.node.kind ~= "prefab" then
		return false, "select one prefab instance to unlink"
	end
	local instance = only.node
	if isRolePrefab(instance.prefab) then
		return false, "a role prefab can't be unlinked"
	end
	local result, why = Resolve.prefab(library, instance.prefab, instance.params)
	if not result then
		return false, why
	end
	local copy = {
		kind = "group",
		id = instance.id,
		name = instance.name,
		transform = deepCopy(instance.transform) or {},
		children = { result.root },
	}
	local used = idsIn(scene.root)
	walk(result.root, function(node)
		for _, key in ipairs({ "material", "color" }) do
			if instance[key] then
				node[key] = deepCopy(instance[key])
			end
		end
		if not node.id or used[node.id] then
			node.id = freshId(node.kind, used)
		end
		used[node.id] = true
	end)
	only.parent.children[only.index] = copy
	scene.selection = { copy.id }
	return true
end

-- What the tree panel calls `node`: its name, else its id.
function Scene.label(node)
	return node.name or node.id
end

return Scene
