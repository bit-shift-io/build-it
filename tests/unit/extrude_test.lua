-- Extruding a shape (src/game/geometry/extrude.lua, triangulate.lua): ear
-- clipping caps and walls along the work plane's normal, a closed mesh.
local Sandbox = require("src.game.script.sandbox")
local Serialize = require("src.game.script.serialize")
local Lockcheck = require("src.game.script.lockcheck")
local Mesh = require("src.game.geometry.mesh")
local Voxelise = require("src.game.geometry.voxelise")
local Triangulate = require("src.game.geometry.triangulate")
local Compile = require("src.game.buildings.compile")
local Scene = require("src.game.builder.scene")
local History = require("src.game.builder.history")
local Properties = require("src.game.builder.properties")
local Config = require("src.game.config")

-- A 2 x 2 square with its north-east tile cut away: area 3.
local L = "{ { 0, 0 }, { 2, 0 }, { 2, 1 }, { 1, 1 }, { 1, 2 }, { 0, 2 } }"
local WALL = "return extrude{ id = \"wall\", height = 1, shape{ points = " .. L .. " } }"

local function run(text)
	local result, message = Sandbox.run(text, "design")
	assertTrue(result, message)
	return result.root
end

local function key(v)
	return string.format("%.6f,%.6f,%.6f", v.x, v.y, v.z)
end

test("ear clipping a concave L gives 4 triangles that tile its area", function()
	local outline = { { 0, 0 }, { 2, 0 }, { 2, 1 }, { 1, 1 }, { 1, 2 }, { 0, 2 } }
	local tris = Triangulate.polygon(outline)
	assertEqual(4, #tris)
	local area = 0
	for _, t in ipairs(tris) do
		local a, b, c = outline[t[1]], outline[t[2]], outline[t[3]]
		local cross = (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1])
		assertTrue(cross > 0, "counter-clockwise")
		area = area + cross / 2
	end
	assertNear(3, area, 1e-9)
end)

test("ear clipping copes with collinear corners", function()
	local outline = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 2, 2 }, { 0, 2 } }
	local area = 0
	for _, t in ipairs(Triangulate.polygon(outline)) do
		local a, b, c = outline[t[1]], outline[t[2]], outline[t[3]]
		area = area + ((b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1])) / 2
	end
	assertNear(4, area, 1e-9)
end)

test("an extruded L is watertight: every edge is shared by exactly two triangles", function()
	local tris = Mesh.ofTree(run(WALL))
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
end)

test("an extruded L costs its voxel volume", function()
	local bp = Compile.design(WALL, "design", { prefabs = {} }, Config)
	assertTrue(bp)
	local perTile = Config.blueprints.voxelsPerTile
	local parts = {}
	for i, t in ipairs(Mesh.parts(run(WALL))) do
		parts[i] = { triangles = Mesh.clip(t), material = "plank" }
	end
	local voxels = Voxelise.of(parts, perTile).plank
	assertEqual(3 * perTile ^ 3, voxels)
	assertEqual(math.ceil(voxels / Config.blueprints.voxelsPerItem.plank.plank), bp.cost.plank)
end)

test("the extrusion follows the plane normal and the height", function()
	-- A vertical plane (u = x, v = z): the normal is -y.
	local root = run("return extrude{ height = 2, shape{ points = { { 0, 0 }, { 1, 0 }, { 1, 1 } },"
		.. " plane = { origin = { 0, 5, 0 }, u = { 1, 0, 0 }, v = { 0, 0, 1 } } } }")
	local b = Mesh.bounds(Mesh.ofTree(root))
	assertNear(3, b.minY, 1e-9)
	assertNear(5, b.maxY, 1e-9)
	assertNear(1, b.maxZ, 1e-9)
end)

test("an extrude node round-trips through the serializer and stays editable", function()
	local root = run(WALL)
	local text = Serialize.tree(root)
	assertEqual(text, Serialize.tree(run(text)))
	local checked = Lockcheck.check(text, "design")
	assertTrue(checked and not checked.locked)
end)

test("extrude needs a height above 0 and exactly one shape", function()
	assertTrue(not Sandbox.run("return extrude{ height = 0, shape{ points = " .. L .. " } }", "d"))
	assertTrue(not Sandbox.run("return extrude{ height = 1 }", "d"))
	assertTrue(not Sandbox.run("return extrude{ height = 1, box{} }", "d"))
end)

test("Scene.extrude wraps the selected shape, one undo step, and the height is a property", function()
	local scene = Scene.new(run("return group{ id = \"root\", shape{ id = \"s\", points = " .. L .. " } }"))
	Scene.ensureIds(scene.root)
	local history = History.new()
	Scene.select(scene, "s", false)
	assertTrue(History.apply(history, scene, Scene.extrude))
	local node = Scene.find(scene, scene.selection[1])
	assertEqual("extrude", node.kind)
	assertEqual("s", node.children[1].id)
	assertEqual(1, #scene.root.children)
	assertTrue(History.apply(history, scene, Properties.set, node.id, "height", 2))
	assertEqual(2, Scene.find(scene, node.id).height)
	assertEqual("height", Properties.of(node)[1].key)
	History.undo(history, scene)
	History.undo(history, scene)
	assertEqual("shape", scene.root.children[1].kind)
end)

test("Scene.extrude refuses anything but a shape", function()
	local scene = Scene.new(run("return group{ id = \"root\", box{ id = \"b\" } }"))
	Scene.select(scene, "b", false)
	local ok, why = Scene.extrude(scene)
	assertTrue(not ok)
	assertTrue(why)
end)

test("the walls and caps wind outward: the signed volume is the area times the height", function()
	for _, plane in ipairs({ "", ", plane = { origin = { 0, 0, 0 }, u = { 1, 0, 0 }, v = { 0, 0, 1 } }" }) do
		local tris = Mesh.ofTree(run("return extrude{ height = 2, shape{ points = " .. L .. plane .. " } }"))
		local volume = 0
		for i = 1, #tris, 3 do
			local a, b, c = tris[i], tris[i + 1], tris[i + 2]
			volume = volume + (a.x * (b.y * c.z - b.z * c.y) - a.y * (b.x * c.z - b.z * c.x) + a.z * (b.x * c.y - b.y * c.x)) / 6
		end
		assertNear(6, volume, 1e-9)
	end
end)
