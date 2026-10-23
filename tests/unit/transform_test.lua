-- Move, rotate and scale in the builder (src/game/builder/transform.lua):
-- how far a drag goes, read from rays through the builder camera, snapped
-- to the grid, and how it changes the selected nodes' transforms.
local Transform = require("src.game.builder.transform")
local BuilderCamera = require("src.app.builder_camera")
local Config = require("src.game.config")

local CFG = Config.builder
local VIEWPORT = { x = 0, y = 40, width = 1280, height = 680 }

-- The ray through the screen pixel where design point p (tiles) shows.
local function rayAt(view, p)
	local s = CFG.studsPerTile
	local sx, sy = BuilderCamera.project(view, p[1] * s, p[2] * s, p[3] * s)
	local o, d = BuilderCamera.ray(view, sx, sy)
	return { o[1] / s, o[2] / s, o[3] / s }, d
end

local function viewOf()
	return BuilderCamera.viewAround(BuilderCamera.new(CFG), { 4, 4, 2 }, 4, CFG, VIEWPORT)
end

test("a move along x follows the pointer's ray to the axis, snapped to a quarter tile", function()
	local view = viewOf()
	local drag = Transform.start("move", { 1, 1, 0.5 }, rayAt(view, { 1, 1, 0.5 }))
	drag.axis = "x"
	local delta = Transform.amount(drag, rayAt(view, { 2.1, 1, 0.5 }))
	assertNear(2.1 - 1 - 0.1, delta[1], 1e-9)
	assertEqual(0, delta[2])
	assertEqual(0, delta[3])
end)

test("a move with no axis slides on the level plane through the centre; free skips the snap", function()
	local view = viewOf()
	local drag = Transform.start("move", { 1, 1, 0.5 }, rayAt(view, { 1, 1, 0.5 }))
	local delta = Transform.amount(drag, rayAt(view, { 2.1, 2.4, 0.5 }))
	assertNear(1, delta[1], 1e-9)
	assertNear(1.5, delta[2], 1e-9)
	assertEqual(0, delta[3])
	local o, d = rayAt(view, { 2.1, 2.4, 0.5 })
	local free = Transform.amount(drag, o, d, true)
	assertNear(1.1, free[1], 1e-9)
	assertNear(1.4, free[2], 1e-9)
end)

test("a rotate turns about z unless an axis is set, by the angle the pointer sweeps, snapped to 15 degrees", function()
	local view = viewOf()
	local c = { 3, 3, 0.5 }
	local a = math.rad(50)
	local drag = Transform.start("rotate", c, rayAt(view, { c[1] + 1, c[2], c[3] }))
	local swept = { c[1] + math.cos(a), c[2] + math.sin(a), c[3] }
	assertNear(45, Transform.amount(drag, rayAt(view, swept)), 1e-9)
	local o, d = rayAt(view, swept)
	assertNear(50, Transform.amount(drag, o, d, true), 1e-6)
	-- About x the sweep is read on the plane facing x: from south to up is +90.
	drag = Transform.start("rotate", c, rayAt(view, { c[1], c[2] + 1, c[3] }))
	drag.axis = "x"
	assertNear(90, Transform.amount(drag, rayAt(view, { c[1], c[2], c[3] + 1 })), 1e-9)
end)

test("a scale is the pointer's distance from the centre over its first, along the axis or on the level plane", function()
	local view = viewOf()
	local c = { 3, 3, 0.5 }
	local drag = Transform.start("scale", c, rayAt(view, { c[1] + 1, c[2], c[3] }))
	drag.axis = "x"
	assertNear(2, Transform.amount(drag, rayAt(view, { c[1] + 2.04, c[2], c[3] })), 1e-9)
	local o, d = rayAt(view, { c[1] + 2.04, c[2], c[3] })
	assertNear(2.04, Transform.amount(drag, o, d, true), 1e-6)
	drag.axis = nil
	assertNear(1.5, Transform.amount(drag, rayAt(view, { c[1], c[2] + 1.5, c[3] })), 1e-9)
	-- Never down to nothing or mirrored.
	assertNear(0.1, Transform.amount(drag, rayAt(view, { c[1], c[2], c[3] })), 1e-9)
end)

local Sandbox = require("src.game.script.sandbox")
local Scene = require("src.game.builder.scene")
local Pick = require("src.game.geometry.pick")
local Mesh = require("src.game.geometry.mesh")

local function sceneOf(text, selection)
	local scene = Scene.new(assert(Sandbox.run(text, "design")).root)
	scene.selection = selection
	return scene
end

-- Node `id`'s geometry bounds in the design's space.
local function boundsOf(scene, id)
	for _, target in ipairs(Pick.targets(scene.root)) do
		if target.id == id then
			return Mesh.bounds(target.triangles)
		end
	end
end

local TURNED = [[
return group{ id = "root",
	group{ id = "wing", transform = { rotate = { 0, 0, 90 }, move = { 4, 0, 0 } },
		box{ id = "post", size = { 1, 1, 2 } },
		box{ id = "beam", size = { 2, 1, 1 }, transform = { move = { 0, 2, 0 } } },
	},
}
]]

test("a move shifts the selected node by the drag in the design's space, whatever its parents' turn", function()
	local scene = sceneOf(TURNED, { "post" })
	local before = boundsOf(scene, "post")
	assertTrue(Transform.apply(scene, { mode = "move", centre = { 0, 0, 0 } }, { 1, 0, 0 }))
	local after = boundsOf(scene, "post")
	assertNear(before.minX + 1, after.minX, 1e-9)
	assertNear(before.minY, after.minY, 1e-9)
	assertNear(before.minZ, after.minZ, 1e-9)
end)

local PAIR = [[
return group{ id = "root",
	box{ id = "west", size = { 1, 1, 1 } },
	box{ id = "east", size = { 1, 1, 1 }, transform = { move = { 3, 0, 0 } } },
	box{ id = "far", size = { 1, 1, 1 }, transform = { move = { 0, 6, 0 } } },
}
]]

test("a multi-selection turns about the centre of its geometry", function()
	local scene = sceneOf(PAIR, { "west", "east" })
	local centre = Transform.centre(scene, Pick.targets(scene.root))
	assertNear(2, centre[1], 1e-9)
	assertNear(0.5, centre[2], 1e-9)
	assertNear(0.5, centre[3], 1e-9)
	assertTrue(Transform.apply(scene, Transform.start("rotate", centre, { 0, 0, 0 }, { 0, 0, -1 }), 90))
	local west, east = boundsOf(scene, "west"), boundsOf(scene, "east")
	-- Turned a quarter about (2, 0.5): west now north of the centre, east south.
	assertNear(1.5, west.minX, 1e-9)
	assertNear(-1.5, west.minY, 1e-9)
	assertNear(1.5, east.minX, 1e-9)
	assertNear(1.5, east.minY, 1e-9)
	assertEqual(90, scene.root.children[1].transform.rotate[3])
	assertEqual(0, boundsOf(scene, "far").minX)
end)

test("moving a group moves its children once, even with a child selected too", function()
	local scene = sceneOf(TURNED, { "post", "wing" })
	local post, beam = boundsOf(scene, "post"), boundsOf(scene, "beam")
	assertTrue(Transform.apply(scene, Transform.start("move", { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, -1 }), { 0, 2, 0 }))
	assertNear(post.minY + 2, boundsOf(scene, "post").minY, 1e-9)
	assertNear(beam.minY + 2, boundsOf(scene, "beam").minY, 1e-9)
	assertEqual(nil, scene.root.children[1].children[1].transform.move)
end)

test("a prefab instance moves; its own nodes are never the scene's to move", function()
	local scene = sceneOf([[return group{ id = "root", prefab("bed", { id = "cot" }) }]], { "cot" })
	assertTrue(Transform.apply(scene, Transform.start("move", { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, -1 }), { 1, 0, 0 }))
	assertEqual(1, scene.root.children[1].transform.move[1])
	scene.selection = { "unknown" }
	assertEqual(false, (Transform.apply(scene, Transform.start("move", { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, -1 }), { 1, 0, 0 })))
end)

test("a scale grows the selection about its centre: evenly, or along a design axis on a turned node", function()
	local scene = sceneOf(PAIR, { "west", "east" })
	local centre = Transform.centre(scene, Pick.targets(scene.root))
	assertTrue(Transform.apply(scene, Transform.start("scale", centre, { 0, 0, 0 }, { 0, 0, -1 }), 2))
	local east = boundsOf(scene, "east")
	assertNear(4, east.minX, 1e-9)
	assertNear(6, east.maxX, 1e-9)
	assertEqual(2, scene.root.children[2].transform.scale[3])
	scene = sceneOf(TURNED, { "beam" })
	local before = boundsOf(scene, "beam")
	-- The beam runs north-south in the design: its own x lies along design y.
	local drag = Transform.start("scale", { before.minX, before.minY, 0 }, { 0, 0, 0 }, { 0, 0, -1 })
	drag.axis = "y"
	assertTrue(Transform.apply(scene, drag, 1.5))
	local after = boundsOf(scene, "beam")
	assertNear((before.maxY - before.minY) * 1.5, after.maxY - after.minY, 1e-9)
	assertNear(before.maxX - before.minX, after.maxX - after.minX, 1e-9)
	assertEqual(1.5, scene.root.children[1].children[2].transform.scale[1])
end)

test("a turn about a design axis holds for a node under a turned parent", function()
	local scene = sceneOf(TURNED, { "post" })
	local centre = Transform.centre(scene, Pick.targets(scene.root))
	local drag = Transform.start("rotate", centre, { 0, 0, 0 }, { 0, 0, -1 })
	drag.axis = "x"
	assertTrue(Transform.apply(scene, drag, 90))
	local b = boundsOf(scene, "post")
	assertNear(3, b.minX, 1e-6)
	assertNear(4, b.maxX, 1e-6)
	assertNear(-0.5, b.minY, 1e-6)
	assertNear(1.5, b.maxY, 1e-6)
	assertNear(0.5, b.minZ, 1e-6)
	assertNear(1.5, b.maxZ, 1e-6)
end)
