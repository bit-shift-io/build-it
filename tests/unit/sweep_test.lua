-- Sweeps (src/game/geometry/sweep.lua): a shape carried along a path on
-- rotation-minimising frames, twisted and scaled linearly along it, mitred
-- at hard corners and capped at both ends: a closed mesh.
local Sweep = require("src.game.geometry.sweep")
local Path = require("src.game.geometry.path")

local function dot(a, b)
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

test("frames along a quarter turn up off the ground keep their side axis: no flip", function()
	-- From (2,0,0) up round to (0,0,2) in the XZ plane at y = 0.
	local xz = { origin = { 0, 0, 0 }, u = { 1, 0, 0 }, v = { 0, 0, 1 } }
	local points = assert(Path.points({ curve = "arc", plane = xz, centre = { 0, 0 }, radius = 2, start = 0, angle = 90 }))
	local frames = Sweep.frames(points)
	assertEqual(#points - 1, #frames)
	for i, f in ipairs(frames) do
		assertNear(0, dot(f.t, f.n), 1e-9)
		assertNear(0, dot(f.t, f.b), 1e-9)
		assertNear(1, math.abs(f.n[2]), 1e-9, "side axis stays along y at frame " .. i)
		if i > 1 then
			assertTrue(dot(f.n, frames[i - 1].n) > 0.99, "no flip at frame " .. i)
		end
	end
end)

local GROUND = { origin = { 0, 0, 0 }, u = { 1, 0, 0 }, v = { 0, 1, 0 } }
local RECT = { points = { { 0, 0 }, { 1, 0 }, { 1, 0.5 }, { 0, 0.5 } }, plane = GROUND }
local WHITE = { 1, 1, 1 }

local function key(v)
	return string.format("%.6f,%.6f,%.6f", v.x, v.y, v.z)
end

-- Whether every edge of `tris` is met once each way: a closed surface.
local function assertWatertight(tris)
	assertTrue(#tris > 0, "has triangles")
	local edges = {}
	for i = 1, #tris, 3 do
		for k = 0, 2 do
			local a, b = key(tris[i + k]), key(tris[i + (k + 1) % 3])
			edges[a .. ">" .. b] = (edges[a .. ">" .. b] or 0) + 1
		end
	end
	for edge, n in pairs(edges) do
		assertEqual(1, n, "edge " .. edge .. " once")
		local a, b = edge:match("^(.-)>(.*)$")
		assertEqual(1, edges[b .. ">" .. a], "edge " .. edge .. " met back once")
	end
end

-- The volume `tris` enclose, above 0 when they wind outward.
local function volume(tris)
	local sum = 0
	for i = 1, #tris, 3 do
		local a, b, c = tris[i], tris[i + 1], tris[i + 2]
		sum = sum + (a.x * (b.y * c.z - b.z * c.y) - a.y * (b.x * c.z - b.z * c.x) + a.z * (b.x * c.y - b.y * c.x)) / 6
	end
	return sum
end

test("a rect swept along an arc is watertight, wound outward, its volume the area times the length", function()
	local arc = { curve = "arc", plane = GROUND, centre = { 0, 0 }, radius = 3, start = 0, angle = 90 }
	local points = assert(Path.points(arc))
	local tris = Sweep.mesh(RECT, points, {}, WHITE)
	assertWatertight(tris)
	-- The profile's centre runs the polygon's length; its area is 0.5.
	local length = 0
	for i = 2, #points do
		local d = { points[i][1] - points[i - 1][1], points[i][2] - points[i - 1][2], points[i][3] - points[i - 1][3] }
		length = length + math.sqrt(dot(d, d))
	end
	assertNear(0.5 * length, volume(tris), 1e-6)
end)

test("twist and scale grow linearly along the path", function()
	local points = { { 0, 0, 1 }, { 1, 0, 1 }, { 4, 0, 1 } }
	local rings = Sweep.rings({ { 0.5, 0 } }, points, { twist = 80, startScale = 1, endScale = 3 })
	-- Along +x the profile's a runs along y and its b up.
	for k, share in ipairs({ 0, 0.25, 1 }) do
		local angle, size = math.rad(80 * share), 1 + 2 * share
		local p = rings[k][1]
		assertNear(points[k][1], p[1], 1e-9)
		assertNear(0.5 * size * math.cos(angle), p[2], 1e-9, "ring " .. k .. " y")
		assertNear(1 + 0.5 * size * math.sin(angle), p[3], 1e-9, "ring " .. k .. " z")
	end
end)

test("a hard corner is mitred: the rect turning a right angle stays watertight, its volume exact", function()
	local points = { { 0, 0, 1 }, { 2, 0, 1 }, { 2, 2, 1 } }
	local tris = Sweep.mesh(RECT, points, {}, WHITE)
	assertWatertight(tris)
	assertNear(0.5 * 4, volume(tris), 1e-9)
	-- The corner ring lies on the plane halving the corner: x - 2 = -y.
	local corner = Sweep.rings({ { 0.5, 0.25 }, { -0.5, 0.25 } }, points, {})[2]
	for _, p in ipairs(corner) do
		assertNear(-(p[2]), p[1] - 2, 1e-9)
	end
end)

local Sandbox = require("src.game.script.sandbox")
local Mesh = require("src.game.geometry.mesh")
local Voxelise = require("src.game.geometry.voxelise")
local Compile = require("src.game.buildings.compile")
local Config = require("src.game.config")

-- A 1 x 1 rect along a quarter arc of radius 3 on a plane a tile up.
local BEAM = [[return sweep{ id = "beam",
	shape{ id = "profile", points = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } } },
	path{ id = "rail", curve = "arc", centre = { 0, 0 }, radius = 3, start = 0, angle = 90,
		plane = { origin = { 0, 0, 1 }, u = { 1, 0, 0 }, v = { 0, 1, 0 } } },
}
]]

local function run(text)
	local result, message = Sandbox.run(text, "design")
	assertTrue(result, message)
	return result.root
end

test("a rect swept along an arc in a script makes a closed curved beam that compiles and voxelises", function()
	local root = run(BEAM)
	local tris = Mesh.ofTree(root)
	assertWatertight(tris)
	local b = Mesh.bounds(tris)
	assertNear(0.5, b.minZ, 1e-9)
	assertNear(1.5, b.maxZ, 1e-9)
	assertNear(3.5, b.maxX, 0.01)
	local bp, why = Compile.design(BEAM, "design", { prefabs = {} }, Config)
	assertTrue(bp, why)
	assertTrue(#bp.mesh > 0)
	local perTile = Config.blueprints.voxelsPerTile
	local voxels = Voxelise.of({ { triangles = Mesh.clip(tris), material = "plank" } }, perTile).plank
	-- About a quarter of the ring from radius 2.5 to 3.5, one tile high.
	local expected = math.pi / 4 * (3.5 ^ 2 - 2.5 ^ 2) * perTile ^ 3
	assertNear(expected, voxels, expected * 0.03)
end)

local Serialize = require("src.game.script.serialize")
local Lockcheck = require("src.game.script.lockcheck")

test("a sweep and every kind of path round-trip through the serializer and stay editable", function()
	local paths = {
		'path{ curve = "line", points = { { 0, 0 }, { 2, 1 } } }',
		'path{ points = { { 0, 0 }, { 2, 0 }, { 2, 2 } } }',
		'path{ curve = "bezier", points = { { 0, 0, 1, 0 }, { 2, 2 } } }',
		'path{ curve = "catmull", points = { { 0, 0 }, { 1, 1 }, { 3, 1 } } }',
		'path{ curve = "arc", radius = 2 }',
		'path{ curve = "helix", turns = 2, pitch = 0.5 }',
	}
	for _, p in ipairs(paths) do
		local text = Serialize.tree(run("return sweep{ twist = 30, endScale = 0.5, shape{ points = { { 0, 0 }, { 1, 0 }, { 1, 1 } } }, " .. p .. " }"))
		assertEqual(text, Serialize.tree(run(text)))
		local checked = Lockcheck.check(text, "design")
		assertTrue(checked and not checked.locked, p .. " stays editable")
	end
end)

test("bad paths and sweeps fail with a message", function()
	local bad = {
		'path{ curve = "spiral" }',
		'path{ curve = "line", points = { { 0, 0 }, { 1, 0 }, { 2, 0 } } }',
		'path{ points = { { 1, 1 }, { 1, 1 } } }',
		'path{ curve = "arc", angle = 0 }',
		'path{ curve = "helix", turns = 1000 }',
		'sweep{ path{ curve = "arc" } }',
		'sweep{ startScale = 0, shape{ points = { { 0, 0 }, { 1, 0 }, { 1, 1 } } }, path{ curve = "arc" } }',
	}
	for _, text in ipairs(bad) do
		local result, message = Sandbox.run("return " .. text, "d")
		assertTrue(not result and message, text .. " fails")
	end
end)

local Pick = require("src.game.geometry.pick")

test("picking a sweep picks the sweep node", function()
	local targets = Pick.targets(run("return group{ id = \"root\", " .. BEAM:gsub("^return ", ""):gsub("\n$", "") .. " }"))
	assertEqual(1, #targets)
	assertEqual("beam", targets[1].id)
end)

local Scene = require("src.game.builder.scene")
local History = require("src.game.builder.history")
local Properties = require("src.game.builder.properties")

local TWO = 'return group{ id = "root", box{ id = "b" }, shape{ id = "s", points = { { 0, 0 }, { 1, 0 }, { 1, 1 } } },'
	.. ' path{ id = "p", curve = "arc", plane = { origin = { 0, 0, 1 }, u = { 1, 0, 0 }, v = { 0, 1, 0 } } } }'

test("Scene.sweep puts the selected shape and the path in a sweep where the path was, one undo step", function()
	local scene = Scene.new(run(TWO))
	local history = History.new()
	Scene.select(scene, "s", false)
	assertTrue(History.apply(history, scene, Scene.sweep, "p"))
	assertEqual(2, #scene.root.children)
	local sweep = scene.root.children[2]
	assertEqual("sweep", sweep.kind)
	assertEqual(sweep.id, scene.selection[1])
	assertEqual("s", sweep.children[1].id)
	assertEqual("p", sweep.children[2].id)
	assertEqual(0, sweep.twist)
	assertEqual(1, sweep.startScale)
	assertEqual(1, sweep.endScale)
	assertTrue(#Mesh.ofTree(scene.root) > 0)
	History.undo(history, scene)
	assertEqual(3, #scene.root.children)
	assertEqual("path", scene.root.children[3].kind)
end)

test("Scene.sweep needs one selected shape and a path, and what is inside a sweep stays put", function()
	local scene = Scene.new(run(TWO))
	Scene.select(scene, "b", false)
	assertTrue(not Scene.sweep(scene, "p"))
	Scene.select(scene, "s", false)
	assertTrue(not Scene.sweep(scene, "b"))
	assertTrue(Scene.sweep(scene, "p"))
	for _, id in ipairs({ "s", "p" }) do
		Scene.select(scene, id, false)
		local ok, why = Scene.delete(scene)
		assertTrue(not ok)
		assertTrue(why:find("inside a sweep"), why)
	end
end)

local function keys(props)
	local out = {}
	for i, p in ipairs(props) do
		out[i] = p.key
	end
	return table.concat(out, " ")
end

test("a sweep's twist and scales and an arc's or helix's params are properties, checked as the API checks them", function()
	local scene = Scene.new(run('return group{ id = "root", ' .. BEAM:gsub("^return ", ""):gsub("\n$", "")
		.. ', path{ id = "coil", curve = "helix" } }'))
	assertEqual("twist startScale endScale", keys(Properties.of(Scene.find(scene, "beam"))))
	assertEqual("radius start angle", keys(Properties.of(Scene.find(scene, "rail"))))
	assertEqual("radius turns pitch", keys(Properties.of(Scene.find(scene, "coil"))))
	assertTrue(Properties.set(scene, "beam", "twist", -45))
	assertEqual(-45, Scene.find(scene, "beam").twist)
	assertTrue(not Properties.set(scene, "beam", "endScale", 0))
	assertTrue(Properties.set(scene, "rail", "start", -30))
	assertTrue(not Properties.set(scene, "rail", "angle", 0))
	assertTrue(not Properties.set(scene, "rail", "angle", 400))
	assertTrue(Properties.set(scene, "rail", "angle", -180))
	assertTrue(Properties.set(scene, "coil", "pitch", -1))
	assertTrue(not Properties.set(scene, "coil", "turns", 100))
	-- What the strip sets still runs: the tree round-trips.
	local text = Serialize.tree(scene.root)
	assertEqual(text, Serialize.tree(run(text)))
end)
