-- Inserting (src/game/builder/insert.lua): the primitives and prefabs the
-- Insert tool offers, the node each one places on the work plane, and the
-- scene edit that adds it.
local Sandbox = require("src.game.script.sandbox")
local Scene = require("src.game.builder.scene")
local Insert = require("src.game.builder.insert")

local function sceneOf(text)
	return Scene.new(assert(Sandbox.run(text, "design")).root)
end

test("an inserted box stands with its origin corner on the placement point, at its default size", function()
	local node = Insert.node({ kind = "box" }, { 1.5, 2, 0 })
	assertEqual("box", node.kind)
	assertEqual(1, node.size[1])
	assertEqual(1.5, node.transform.move[1])
	assertEqual(2, node.transform.move[2])
	assertEqual(0, node.transform.move[3])
end)

test("an inserted sphere rests on the plane; a prefab is an instance by name", function()
	local ball = Insert.node({ kind = "sphere" }, { 0, 0, 0 })
	assertEqual(0.5, ball.transform.move[3])
	local saw = Insert.node({ prefab = "saw" }, { 2, 1, 0 })
	assertEqual("prefab", saw.kind)
	assertEqual("saw", saw.prefab)
	assertEqual(2, saw.transform.move[1])
end)

test("the menu offers every primitive, then every library prefab by name, role prefabs included", function()
	local items = Insert.items({ designs = {}, prefabs = { saw = "", bed = "", input_port = "" } })
	local labels = {}
	for i, item in ipairs(items) do
		labels[i] = item.label
	end
	assertEqual("Box, Sphere, Cylinder, Cone, Wedge, bed, input_port, saw", table.concat(labels, ", "))
	assertEqual("cone", items[4].kind)
	assertEqual("bed", items[6].prefab)
end)

test("inserting adds the node to the root group with a fresh id and selects it, one undoable step", function()
	local History = require("src.game.builder.history")
	local scene = sceneOf('return group{ id = "root", box{ id = "box1" } }')
	local history = History.new()
	assertTrue(History.apply(history, scene, Scene.insert, Insert.node({ kind = "box" }, { 0, 0, 0 })))
	assertTrue(History.apply(history, scene, Scene.insert, Insert.node({ prefab = "saw" }, { 1, 0, 0 })))
	assertEqual(3, #scene.root.children)
	assertEqual("box2", scene.root.children[2].id)
	assertEqual("saw1", scene.root.children[3].id)
	assertEqual("saw1", scene.selection[1])
	History.undo(history, scene)
	assertEqual(2, #scene.root.children)
end)

test("inserting into a design whose root is one node groups the two under a new root", function()
	local scene = sceneOf('return box{ id = "base" }')
	assertTrue(Scene.insert(scene, Insert.node({ kind = "cone" }, { 0, 0, 0 })))
	assertEqual("group", scene.root.kind)
	assertEqual("base", scene.root.children[1].id)
	assertEqual("cone1", scene.root.children[2].id)
end)
