-- Lathing a shape (src/game/geometry/lathe.lua): a profile revolved about
-- its plane's v axis, closed at 360 degrees and capped otherwise.
local Sandbox = require("src.game.script.sandbox")
local Serialize = require("src.game.script.serialize")
local Lockcheck = require("src.game.script.lockcheck")
local Mesh = require("src.game.geometry.mesh")
local Voxelise = require("src.game.geometry.voxelise")
local Compile = require("src.game.buildings.compile")
local Scene = require("src.game.builder.scene")
local History = require("src.game.builder.history")
local Properties = require("src.game.builder.properties")
local Config = require("src.game.config")

-- A rectangle from 1 to 2 tiles out of the axis, 3 tall: a ring's profile.
local RECT = "{ { 1, 0 }, { 2, 0 }, { 2, 3 }, { 1, 3 } }"
local VERTICAL = ", plane = { origin = { 0, 0, 0 }, u = { 1, 0, 0 }, v = { 0, 0, 1 } }"

local function run(text)
	local result, message = Sandbox.run(text, "design")
	assertTrue(result, message)
	return result.root
end

local function pillar(extra)
	return "return lathe{ id = \"p\", " .. (extra or "") .. "shape{ points = " .. RECT .. VERTICAL .. " } }"
end

local function key(v)
	return string.format("%.6f,%.6f,%.6f", v.x, v.y, v.z)
end

local function volume(tris)
	local sum = 0
	for i = 1, #tris, 3 do
		local a, b, c = tris[i], tris[i + 1], tris[i + 2]
		sum = sum + (a.x * (b.y * c.z - b.z * c.y) - a.y * (b.x * c.z - b.z * c.x) + a.z * (b.x * c.y - b.y * c.x)) / 6
	end
	return sum
end

local function assertWatertight(tris)
	local edges = {}
	for i = 1, #tris, 3 do
		for k = 0, 2 do
			local a, b = key(tris[i + k]), key(tris[i + (k + 1) % 3])
			edges[a .. ">" .. b] = (edges[a .. ">" .. b] or 0) + 1
		end
	end
	local count = 0
	for edge, n in pairs(edges) do
		assertEqual(1, n)
		local a, b = edge:match("^(.-)>(.*)$")
		assertEqual(1, edges[b .. ">" .. a], "opposite edge present once")
		count = count + 1
	end
	assertTrue(count > 0)
end

test("a rect lathed 360 degrees is watertight with a ring's volume", function()
	local tris = Mesh.ofTree(run(pillar("segments = 64, ")))
	assertWatertight(tris)
	local ring = math.pi * (4 - 1) * 3
	-- 64 chords fall a little short of the true circle.
	assertNear(ring, volume(tris), ring * 0.01)
	assertTrue(volume(tris) < ring)
end)

test("a partial lathe is capped and watertight, wound outward both ways", function()
	for _, angle in ipairs({ 90, -90 }) do
		local tris = Mesh.ofTree(run(pillar("angle = " .. angle .. ", segments = 32, ")))
		assertWatertight(tris)
		local quarter = math.pi * 3 * 3 / 4
		assertNear(quarter, volume(tris), quarter * 0.01)
	end
end)

test("a profile touching the axis lathes into a solid pillar", function()
	local tris = Mesh.ofTree(run("return lathe{ segments = 64, shape{ points = { { 0, 0 }, { 1, 0 }, { 1, 2 }, { 0, 2 } }" .. VERTICAL .. " } }"))
	assertWatertight(tris)
	assertNear(math.pi * 2, volume(tris), math.pi * 2 * 0.01)
end)

test("the turn goes toward the plane normal and around the v axis", function()
	-- u = x, v = z: the normal is -y, so a quarter turn ends on the -y side.
	local b = Mesh.bounds(Mesh.ofTree(run(pillar("angle = 90, segments = 16, "))))
	assertNear(-2, b.minY, 1e-9)
	assertNear(0, b.maxY, 1e-9)
	assertNear(0, b.minX, 1e-9)
	assertNear(2, b.maxX, 1e-9)
end)

test("a pillar costs its voxel volume", function()
	local bp = Compile.design(pillar(), "design", { prefabs = {} }, Config)
	assertTrue(bp)
	assertTrue(bp.cost.plank > 0)
	local parts = {}
	for i, t in ipairs(Mesh.parts(run(pillar()))) do
		parts[i] = { triangles = Mesh.clip(t), material = "plank" }
	end
	local voxels = Voxelise.of(parts, Config.blueprints.voxelsPerTile).plank
	assertTrue(voxels > 0)
	assertEqual(math.ceil(voxels / Config.blueprints.voxelsPerItem.plank.plank), bp.cost.plank)
end)

test("a lathe node round-trips through the serializer and stays editable", function()
	local text = Serialize.tree(run(pillar("angle = 180, segments = 12, ")))
	assertEqual(text, Serialize.tree(run(text)))
	local checked = Lockcheck.check(text, "design")
	assertTrue(checked and not checked.locked)
end)

test("lathe needs one shape and an angle from -360 to 360, not 0", function()
	assertTrue(not Sandbox.run("return lathe{ }", "d"))
	assertTrue(not Sandbox.run("return lathe{ box{} }", "d"))
	assertTrue(not Sandbox.run(pillar("angle = 0, "), "d"))
	assertTrue(not Sandbox.run(pillar("angle = 361, "), "d"))
	assertTrue(not Sandbox.run(pillar("segments = 2, "), "d"))
	assertTrue(not Sandbox.run(pillar("segments = 65, "), "d"))
end)

test("a profile crossing the axis makes no mesh", function()
	local tris = Mesh.ofTree(run("return group{ box{}, lathe{ shape{ points = { { -1, 0 }, { 1, 0 }, { 1, 2 }, { -1, 2 } }" .. VERTICAL .. " } } }"))
	assertEqual(36, #tris)
end)

test("Scene.lathe wraps the selected shape, one undo step, angle and segments are properties", function()
	local scene = Scene.new(run("return group{ id = \"root\", shape{ id = \"s\", points = " .. RECT .. VERTICAL .. " } }"))
	Scene.ensureIds(scene.root)
	local history = History.new()
	Scene.select(scene, "s", false)
	assertTrue(History.apply(history, scene, Scene.lathe))
	local node = Scene.find(scene, scene.selection[1])
	assertEqual("lathe", node.kind)
	assertEqual("s", node.children[1].id)
	assertEqual("angle", Properties.of(node)[1].key)
	assertEqual("segments", Properties.of(node)[2].key)
	assertTrue(History.apply(history, scene, Properties.set, node.id, "angle", 180))
	assertEqual(180, Scene.find(scene, node.id).angle)
	assertTrue(not Properties.set(scene, node.id, "angle", 0))
	assertTrue(not Properties.set(scene, node.id, "segments", 2))
	History.undo(history, scene)
	History.undo(history, scene)
	assertEqual("shape", scene.root.children[1].kind)
end)

test("Scene.lathe refuses a non-shape and a shape across the axis", function()
	local scene = Scene.new(run("return group{ id = \"root\", box{ id = \"b\" }, shape{ id = \"s\", points = { { -1, 0 }, { 1, 0 }, { 1, 2 } } } }"))
	Scene.select(scene, "b", false)
	local ok, why = Scene.lathe(scene)
	assertTrue(not ok and why)
	Scene.select(scene, "s", false)
	ok, why = Scene.lathe(scene)
	assertTrue(not ok and why)
end)
