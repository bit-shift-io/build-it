-- Contextual actions (src/game/builder/actions.lua): which labels the
-- context menu offers for a selection.
local Actions = require("src.game.builder.actions")
local Scene = require("src.game.builder.scene")
local Sandbox = require("src.game.script.sandbox")

local function sceneOf(text)
	local result = assert(Sandbox.run(text, "t"))
	return Scene.new(result.root)
end

local TEXT = [[
return group{ id = "root",
	shape{ id = "bare", points = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } } },
	shape{ id = "ex", points = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } } },
	path{ id = "p", points = { { 0, 0 }, { 3, 0 } } },
	box{ id = "b" },
	prefab("something", { id = "plain" }),
	prefab("bed", { id = "role" }),
}
]]

local function has(list, label)
	for _, l in ipairs(list) do
		if l == label then
			return true
		end
	end
	return false
end

test("nothing selected lists only the whole-design actions", function()
	local scene = sceneOf(TEXT)
	assertEqual("Rename,Export as prefab,Reset to default", table.concat(Actions.of(scene, {}, nil, false), ","))
end)

test("a bare shape and a bare path get Make 3D", function()
	local scene = sceneOf(TEXT)
	assertTrue(has(Actions.of(scene, { "bare" }, nil, false), "Make 3D"))
	assertTrue(has(Actions.of(scene, { "p" }, nil, false), "Make 3D"))
	assertFalse(has(Actions.of(scene, { "b" }, nil, false), "Make 3D"))
end)

test("an extruded shape has no Make 3D", function()
	local scene = sceneOf(TEXT)
	Scene.select(scene, "ex", false)
	assertTrue(Scene.extrude(scene))
	assertFalse(has(Actions.of(scene, { "ex" }, nil, false), "Make 3D"))
	assertTrue(has(Actions.of(scene, { scene.selection[1] }, nil, false), "Delete"))
end)

test("a role prefab instance has no Unlink, a plain one does", function()
	local scene = sceneOf(TEXT)
	local role = Actions.of(scene, { "role" }, nil, false)
	assertFalse(has(role, "Unlink"))
	assertTrue(has(role, "Edit prefab"))
	local plain = Actions.of(scene, { "plain" }, nil, false)
	assertTrue(has(plain, "Unlink"))
	assertTrue(has(plain, "Edit prefab"))
end)

test("a group of nodes gets no Rename or Make 3D", function()
	local scene = sceneOf(TEXT)
	local list = Actions.of(scene, { "bare", "p" }, nil, false)
	assertFalse(has(list, "Rename"))
	assertFalse(has(list, "Make 3D"))
	assertTrue(has(list, "Group"))
end)

test("a locked script gets no Make 3D", function()
	local scene = sceneOf(TEXT)
	assertFalse(has(Actions.of(scene, { "bare" }, nil, true), "Make 3D"))
	assertTrue(has(Actions.of(scene, { "bare" }, nil, false), "Make 3D"))
end)

test("Make 3D opens Extrude, Lathe, Sweep and Back for a shape; a sweep entry and Back for a path", function()
	assertEqual("Extrude,Lathe,Sweep along path…,◂ Back", table.concat(Actions.make3d("shape"), ","))
	assertEqual("Sweep a shape along this…,◂ Back", table.concat(Actions.make3d("path"), ","))
end)

test("the list never offers Material or Colour; showPaint needs a node with volume", function()
	local scene = sceneOf(TEXT)
	assertFalse(has(Actions.of(scene, { "b" }, nil, false), "Material"))
	assertFalse(has(Actions.of(scene, { "b" }, nil, false), "Colour"))
	assertTrue(Actions.showPaint(scene, { "b" }))
	assertTrue(Actions.showPaint(scene, { "bare", "b" }))
	assertFalse(Actions.showPaint(scene, { "bare", "p" }))
	assertFalse(Actions.showPaint(scene, {}))
end)
