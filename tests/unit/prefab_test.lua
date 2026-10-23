-- Prefab instances (docs/CONTEXT.md "Prefab", "Param", "Role prefab"):
-- an instance is one node with param overrides (src/game/script/resolve.lua),
-- exported from a selection and unlinked into an editable copy
-- (src/game/builder/scene.lua), over a design library whose built-ins a
-- saved script shadows until reset (src/game/designs/library.lua).
local Sandbox = require("src.game.script.sandbox")
local Resolve = require("src.game.script.resolve")
local Serialize = require("src.game.script.serialize")
local Lockcheck = require("src.game.script.lockcheck")

local TABLE = [[
local width = UI.number({ default = 1, min = 0.5, max = 4 })
local legs = UI.bool({ default = true })
return group{ id = "table",
	box{ id = "top", size = { width, 1, 0.25 }, transform = { move = { 0, 0, 1 } } },
	legs and box{ id = "leg", size = { 0.25, 0.25, 1 } } or nil,
}
]]

local function libraryWith(prefabs)
	return { designs = {}, prefabs = prefabs }
end

-- The resolved node with id `id` under `node`, or nil.
local function find(node, id)
	if node.id == id then
		return node
	end
	for _, child in ipairs(node.children or {}) do
		local found = find(child, id)
		if found then
			return found
		end
	end
end

test("an instance's param overrides apply to its prefab, by param name", function()
	local design = 'return group{ id = "root", prefab("table", { id = "t", params = { width = 3, legs = false } }) }'
	local resolved = assert(Resolve.design(design, "design", libraryWith({ table = TABLE })))
	local top = assert(find(resolved.root, "top"))
	assertEqual(3, top.size[1])
	assertEqual(nil, find(resolved.root, "leg"), "legs = false drops the leg")
	local plain = assert(Resolve.design('return prefab("table")', "design", libraryWith({ table = TABLE })))
	assertEqual(1, find(plain.root, "top").size[1])
end)

test("an instance's material and colour apply to every node in it, over the prefab's own", function()
	local chair = [[
return group{ id = "chair",
	box{ id = "seat", color = { 1, 0, 0 }, material = { name = "plank", variant = "bark" } },
	prefab("table", { id = "inner" }),
}
]]
	local design = 'return group{ id = "root", prefab("chair", { id = "c", color = "primary", material = { name = "stone" } }) }'
	local resolved = assert(Resolve.design(design, "design", libraryWith({ table = TABLE, chair = chair })))
	local seat, top = find(resolved.root, "seat"), find(resolved.root, "top")
	assertEqual("primary", seat.color)
	assertEqual("stone", seat.material.name)
	assertEqual("primary", top.color, "a prefab inside the instance takes it too")
	assertEqual("stone", top.material.name)
end)

test("an instance's overrides round trip and leave the design editable", function()
	local text = 'return group{ id = "root", prefab("table", { id = "t", params = { legs = false, tint = { 1, 0.5, 0 }, width = 2.5 } }) }\n'
	local checked = assert(Lockcheck.check(text, "design"))
	assertFalse(checked.locked, "overrides are literal fields")
	local again = Serialize.tree(checked.root)
	local params = assert(Sandbox.run(again, "design")).root.children[1].params
	assertEqual(2.5, params.width)
	assertEqual(false, params.legs)
	assertEqual(0.5, params.tint[2])
	local _, message = Sandbox.run('return prefab("table", { params = { 3 } })', "design")
	assertTrue(message and message:find("named", 1, true), message)
end)

local Scene = require("src.game.builder.scene")
local Mesh = require("src.game.geometry.mesh")

local function sceneOf(text)
	return Scene.new(assert(Sandbox.run(text, "design")).root)
end

-- Every vertex of the scene's resolved geometry, in tree order, rounded.
local function vertices(scene, library)
	local resolved = assert(Resolve.design(Serialize.tree(scene.root), "design", library))
	local out = {}
	for _, part in ipairs(Mesh.parts(resolved.root)) do
		for _, v in ipairs(part) do
			out[#out + 1] = string.format("%.4f %.4f %.4f %.2f %.2f %.2f", v.x, v.y, v.z, v.r, v.g, v.b)
		end
	end
	table.sort(out)
	return table.concat(out, "\n")
end

local YARD = [[
return group{ id = "root", transform = { move = { 1, 0, 0 } },
	group{ id = "shed", transform = { move = { 2, 1, 0 }, rotate = { 0, 0, 90 } }, color = { 0, 0, 1 },
		box{ id = "wall", size = { 1, 0.5, 1 }, transform = { move = { 0.5, 0, 0 } } },
	},
	sphere{ id = "ball", transform = { move = { 0, 3, 0.5 }, scale = 2 } },
	box{ id = "path", size = { 3, 1, 0.1 } },
}
]]

test("exporting nodes from different groups keeps every world transform and look", function()
	local scene, library = sceneOf(YARD), libraryWith({})
	local before = vertices(scene, library)
	Scene.select(scene, "wall")
	Scene.select(scene, "ball", true)
	local ok, text = Scene.export(scene, "kit", library)
	assertTrue(ok, text)
	library.prefabs.kit = text
	assertEqual(before, vertices(scene, library))
	local instance = Scene.find(scene, scene.selection[1])
	assertEqual("prefab", instance.kind)
	assertEqual("kit", instance.prefab)
	assertEqual(nil, Scene.find(scene, "wall"), "the selection left the design")
	assertEqual(nil, Scene.find(scene, "ball"))
	assertEqual(instance, scene.root.children[1], "the instance stands where the first of them did")
end)

test("exporting as a prefab the selection already uses, however deep, is refused as a cycle", function()
	local library = libraryWith({ table = TABLE, chair = 'return group{ id = "chair", prefab("table") }\n' })
	local scene = sceneOf('return group{ id = "root", prefab("chair", { id = "c" }), box{ id = "b" } }')
	Scene.select(scene, "c")
	Scene.select(scene, "b", true)
	local ok, why = Scene.export(scene, "table", library)
	assertFalse(ok)
	assertTrue(why:find("prefab cycle", 1, true), why)
	assertEqual("chair", scene.root.children[1].prefab, "the scene is unchanged")
	assertEqual(2, #scene.root.children)
end)

test("unlinking an instance replaces it with an editable copy that looks the same", function()
	local library = libraryWith({ table = TABLE })
	local scene = sceneOf([[
return group{ id = "root", box{ id = "top" },
	prefab("table", { id = "t", color = "primary", params = { width = 2 }, transform = { move = { 1, 2, 0 }, rotate = { 0, 0, 90 } } }),
}
]])
	local before = vertices(scene, library)
	Scene.select(scene, "t")
	local ok, why = Scene.unlink(scene, library)
	assertTrue(ok, why)
	assertEqual(before, vertices(scene, library))
	local copy = scene.root.children[2]
	assertEqual("group", copy.kind)
	assertEqual("t", copy.id)
	assertEqual(copy.id, scene.selection[1])
	local ids = {}
	for _, row in ipairs(Scene.rows(scene)) do
		assertFalse(ids[row.node.id], "ids stay unique: " .. row.node.id)
		ids[row.node.id] = true
	end
	assertTrue(#Scene.rows(scene) >= 5, "the copy's nodes are the design's now")
	assertFalse(assert(Lockcheck.check(Serialize.tree(scene.root), "design")).locked, "and editable")
end)

test("a role prefab can't be unlinked, and only a prefab instance can", function()
	local Builtins = require("tests.support.builtins")
	local scene = sceneOf('return group{ id = "root", prefab("bed", { id = "bed" }), box{ id = "b" } }')
	Scene.select(scene, "bed")
	local ok, why = Scene.unlink(scene, Builtins)
	assertFalse(ok)
	assertTrue(why:find("role prefab", 1, true), why)
	assertEqual("prefab", scene.root.children[1].kind)
	Scene.select(scene, "b")
	ok, why = Scene.unlink(scene, Builtins)
	assertFalse(ok)
	assertTrue(why:find("prefab instance", 1, true), why)
end)

test("setting an instance's param overrides it, and the prefab's params show the value", function()
	local library = libraryWith({ table = TABLE })
	local scene = sceneOf('return group{ id = "root", prefab("table", { id = "t" }), box{ id = "b" } }')
	assertTrue(Scene.setParam(scene, "t", "width", 3))
	assertEqual(3, Scene.find(scene, "t").params.width)
	local result = assert(Resolve.prefab(library, "table", Scene.find(scene, "t").params))
	assertEqual("width", result.params[1].name)
	assertEqual(3, result.params[1].value)
	assertEqual(1, result.params[1].default)
	assertTrue(result.params[2].value, "an unset param keeps its default")
	local ok, why = Scene.setParam(scene, "b", "width", 3)
	assertFalse(ok)
	assertTrue(why:find("prefab instance", 1, true), why)
end)

test("rows show an expanded instance's own tree under it, read-only and owned by the instance", function()
	local library = libraryWith({ table = TABLE })
	local scene = sceneOf('return group{ id = "root", prefab("table", { id = "t" }), box{ id = "b" } }')
	local inside = assert(Resolve.prefab(library, "table")).root
	local rows = Scene.rows(scene, { t = inside })
	assertEqual(6, #rows)
	assertEqual("t", rows[2].node.id)
	assertFalse(rows[2].readOnly, "the instance itself is the design's")
	assertEqual("table", rows[3].node.id)
	assertTrue(rows[3].readOnly)
	assertEqual("t", rows[3].owner)
	assertEqual(2, rows[3].depth)
	assertEqual("top", rows[4].node.id)
	assertEqual(3, rows[4].depth)
	assertEqual("b", rows[6].node.id)
	assertFalse(rows[6].readOnly)
	assertEqual(3, #Scene.rows(scene), "unexpanded, an instance is one row")
end)

local Library = require("src.game.designs.library")

test("a saved built-in is a shadow: reset drops it, and built-ins can't be deleted or renamed", function()
	local Builtins = require("tests.support.builtins")
	local saved = { designs = { mill = "return box{}\n" }, prefabs = { bed = "return box{}\n", kit = "return box{}\n" } }
	assertTrue(Library.builtin("prefabs", "bed"))
	assertFalse(Library.builtin("prefabs", "kit"))
	assertTrue(Library.builtin("designs", "storage_facility"))
	local reset = assert(Library.reset(saved, "prefabs", "bed"))
	assertEqual(nil, reset.prefabs.bed)
	assertEqual("return box{}\n", saved.prefabs.bed, "the saved table is left as it was")
	assertEqual(Builtins.prefabs.bed, Library.merge(Builtins, reset).prefabs.bed, "the built-in shows again")
	local _, why = Library.reset(reset, "prefabs", "bed")
	assertTrue(why:find("default", 1, true), why)
	_, why = Library.reset(saved, "prefabs", "kit")
	assertTrue(why:find("built-in", 1, true), why)
	local ok
	ok, why = Library.removable("prefabs", "bed")
	assertFalse(ok)
	assertTrue(why:find("can't be deleted or renamed", 1, true), why)
	assertTrue(Library.removable("prefabs", "kit"))
end)
