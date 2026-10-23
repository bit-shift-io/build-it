-- The builder's scene (src/game/builder/scene.lua) and its undo history
-- (src/game/builder/history.lua): a design script's node tree, its
-- selection, and the tree panel's edits.
local Sandbox = require("src.game.script.sandbox")
local Scene = require("src.game.builder.scene")

local function sceneOf(text)
	return Scene.new(assert(Sandbox.run(text, "design")).root)
end

local HOUSE = [[
return group{ id = "root", name = "House",
	box{ id = "base", name = "Base" },
	group{ id = "roof", name = "Roof", sphere{ id = "dome" } },
	box{ size = { 1, 1, 2 } },
}
]]

test("every node gets an id: unnamed ones a fresh one, and the rows list them by depth", function()
	local scene = sceneOf(HOUSE)
	local rows = Scene.rows(scene)
	assertEqual(5, #rows)
	assertEqual("root", rows[1].node.id)
	assertEqual(0, rows[1].depth)
	assertEqual("dome", rows[4].node.id)
	assertEqual(2, rows[4].depth)
	assertEqual("box1", rows[5].node.id)
	assertEqual("House", Scene.label(rows[1].node))
	assertEqual("box1", Scene.label(rows[5].node))
end)

test("a click selects one node; an added click toggles it in the selection", function()
	local scene = sceneOf(HOUSE)
	Scene.select(scene, "base")
	Scene.select(scene, "dome", true)
	assertEqual(2, #scene.selection)
	assertTrue(Scene.isSelected(scene, "dome"))
	Scene.select(scene, "base", true)
	assertFalse(Scene.isSelected(scene, "base"))
	Scene.select(scene, "roof")
	assertEqual(1, #scene.selection)
	assertEqual("roof", scene.selection[1])
	Scene.select(scene, nil)
	assertEqual(0, #scene.selection)
end)

test("rename names a node; an empty name clears it back to the id", function()
	local scene = sceneOf(HOUSE)
	assertTrue(Scene.rename(scene, "dome", "Cupola"))
	assertEqual("Cupola", Scene.find(scene, "dome").name)
	assertTrue(Scene.rename(scene, "dome", ""))
	assertEqual(nil, Scene.find(scene, "dome").name)
end)

test("delete removes the selected nodes and their children, never the root", function()
	local scene = sceneOf(HOUSE)
	Scene.select(scene, "roof")
	Scene.select(scene, "base", true)
	assertTrue(Scene.delete(scene))
	assertEqual(2, #Scene.rows(scene))
	assertEqual(nil, Scene.find(scene, "dome"))
	assertEqual(0, #scene.selection)
	Scene.select(scene, "root")
	local ok, reason = Scene.delete(scene)
	assertFalse(ok)
	assertEqual("string", type(reason))
	assertEqual(2, #Scene.rows(scene))
end)

test("duplicate copies each selected node after it with fresh ids, and selects the copies", function()
	local scene = sceneOf(HOUSE)
	Scene.select(scene, "roof")
	assertTrue(Scene.duplicate(scene))
	local root = scene.root
	assertEqual(4, #root.children)
	local copy = root.children[3]
	assertEqual("Roof", copy.name)
	assertEqual("group1", copy.id)
	assertEqual("sphere1", copy.children[1].id)
	assertEqual("group1", scene.selection[1])
	copy.children[1].radius = 9
	assertEqual(0.5, Scene.find(scene, "dome").radius)
end)

test("group wraps the selected siblings in a new group where the first was", function()
	local scene = sceneOf(HOUSE)
	Scene.select(scene, "box1")
	Scene.select(scene, "base", true)
	assertTrue(Scene.group(scene))
	local root = scene.root
	assertEqual(2, #root.children)
	local group = root.children[1]
	assertEqual("group", group.kind)
	assertEqual("Group", group.name)
	assertEqual("base", group.children[1].id)
	assertEqual("box1", group.children[2].id)
	assertEqual(group.id, scene.selection[1])
end)

test("group refuses nodes under different parents, and the root", function()
	local scene = sceneOf(HOUSE)
	Scene.select(scene, "base")
	Scene.select(scene, "dome", true)
	assertFalse(Scene.group(scene))
	Scene.select(scene, "root")
	assertFalse(Scene.group(scene))
	assertEqual(3, #scene.root.children)
end)

local History = require("src.game.builder.history")

test("undo steps back over an edit that took and redo steps forward again; refused edits leave no step", function()
	local scene = sceneOf(HOUSE)
	local history = History.new()
	History.apply(history, scene, Scene.rename, "base", "Floor")
	Scene.select(scene, "root")
	assertFalse(History.apply(history, scene, Scene.delete))
	Scene.select(scene, "roof")
	History.apply(history, scene, Scene.delete)
	assertEqual(nil, Scene.find(scene, "dome"))

	assertTrue(History.undo(history, scene))
	assertEqual("dome", Scene.find(scene, "dome").id)
	assertTrue(History.undo(history, scene))
	assertEqual("Base", Scene.find(scene, "base").name)
	assertFalse(History.undo(history, scene))

	assertTrue(History.redo(history, scene))
	assertEqual("Floor", Scene.find(scene, "base").name)
	History.apply(history, scene, Scene.rename, "base", "Plinth")
	assertFalse(History.redo(history, scene))
end)

test("setMaterial makes every selected node, the root too, of a material; a bad one is refused", function()
	local History = require("src.game.builder.history")
	local scene = sceneOf(HOUSE)
	local history = History.new()
	Scene.select(scene, "root")
	Scene.select(scene, "dome", true)
	local material = { name = "stone", variant = "brick", scale = 2, rotation = 45 }
	assertTrue(History.apply(history, scene, Scene.setMaterial, material))
	assertEqual("brick", Scene.find(scene, "root").material.variant)
	assertEqual(45, Scene.find(scene, "dome").material.rotation)
	assertEqual(nil, Scene.find(scene, "base").material)
	material.variant = "rough"
	assertEqual("brick", Scene.find(scene, "dome").material.variant, "the node keeps its own copy")

	local ok, why = Scene.setMaterial(scene, { name = "plank", variant = "brick" })
	assertFalse(ok)
	assertTrue(why:find("variant", 1, true), why)

	History.undo(history, scene)
	assertEqual(nil, Scene.find(scene, "root").material)
	Scene.select(scene, nil)
	ok, why = Scene.setMaterial(scene, material)
	assertFalse(ok)
	assertEqual("nothing selected", why)
end)

test("a node's material is its own, else the nearest one above it, else none", function()
	local scene = sceneOf([[
return group{ id = "root", material = { name = "stone" },
	group{ id = "g", material = { name = "plank", variant = "bark" }, box{ id = "b" } },
	box{ id = "c" },
}
]])
	assertEqual("bark", Scene.material(scene, "b").variant)
	assertEqual("stone", Scene.material(scene, "c").name)
	assertEqual(nil, Scene.material(sceneOf("return group{ id = \"root\", box{ id = \"b\" } }"), "b"))
end)
