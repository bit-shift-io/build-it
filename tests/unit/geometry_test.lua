-- Geometry (src/game/geometry/): a design script's node tree turned into one
-- triangle list in the mesher's vertex format, its bounds, the footprint
-- they round up to, and the clip at ground level. Trees come from the
-- sandbox, as the builder gets them.
local Sandbox = require("src.game.script.sandbox")
local Mesh = require("src.game.geometry.mesh")
local Footprint = require("src.game.geometry.footprint")

local function tree(text)
	return assert(Sandbox.run(text, "design")).root
end

local function boundsOf(text)
	return Mesh.bounds(Mesh.ofTree(tree(text)))
end

local function assertBounds(expected, b)
	local names = { "minX", "minY", "minZ", "maxX", "maxY", "maxZ" }
	for i, name in ipairs(names) do
		assertNear(expected[i], b[name], 1e-6, name .. " was " .. tostring(b[name]))
	end
end

test("a box spans its size from the origin", function()
	assertBounds({ 0, 0, 0, 2, 1, 3 }, boundsOf("return box{ size = { 2, 1, 3 } }"))
end)

-- Every triangle wound so cross(b - a, c - a) points along its normal.
local function assertOutward(triangles)
	assertTrue(#triangles > 0 and #triangles % 3 == 0, "expected whole triangles")
	for i = 1, #triangles, 3 do
		local a, b, c = triangles[i], triangles[i + 1], triangles[i + 2]
		local ux, uy, uz = b.x - a.x, b.y - a.y, b.z - a.z
		local vx, vy, vz = c.x - a.x, c.y - a.y, c.z - a.z
		local cx, cy, cz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
		local d = cx * a.nx + cy * a.ny + cz * a.nz
		assertTrue(d >= -1e-9, "triangle " .. ((i + 2) / 3) .. " faces inward")
	end
end

test("a box's triangles face outward", function()
	assertOutward(Mesh.ofTree(tree("return box{ size = { 2, 1, 3 } }")))
end)

test("a sphere spans its radius about the origin, faces outward, and keeps its normals unit length", function()
	local triangles = Mesh.ofTree(tree("return sphere{ radius = 1.5, transform = { move = { 0, 0, 2 } } }"))
	assertBounds({ -1.5, -1.5, 0.5, 1.5, 1.5, 3.5 }, Mesh.bounds(triangles))
	assertOutward(triangles)
	for _, v in ipairs(triangles) do
		assertNear(1, math.sqrt(v.nx * v.nx + v.ny * v.ny + v.nz * v.nz), 1e-6)
	end
end)

test("a transform scales, then rotates, then moves", function()
	-- A unit box stretched to 2 along x, turned 90 degrees about z (x onto
	-- y), then moved 5 east: x -1..0 and y 0..2 before the move.
	local b = boundsOf("return box{ transform = { scale = { 2, 1, 1 }, rotate = { 0, 0, 90 }, move = { 5, 0, 0 } } }")
	assertBounds({ 4, 0, 0, 5, 2, 1 }, b)
end)

test("a scaled sphere stretches along the scaled axis", function()
	local b = boundsOf("return sphere{ radius = 1, transform = { scale = { 2, 1, 0.5 } } }")
	assertBounds({ -2, -1, -0.5, 2, 1, 0.5 }, b)
end)

test("a group's transform applies after its children's", function()
	local b = boundsOf([[
return group{ transform = { move = { 10, 0, 0 }, scale = 2 },
	box{ transform = { move = { 1, 0, 0 } } },
	box{ size = { 1, 3, 1 } },
}]])
	assertBounds({ 10, 0, 0, 14, 6, 2 }, b)
end)

test("a mirroring scale keeps triangles facing outward", function()
	assertOutward(Mesh.ofTree(tree("return box{ transform = { scale = { -1, 1, 1 } } }")))
end)

test("an empty group has no triangles and no bounds", function()
	local triangles = Mesh.ofTree(tree("return group{}"))
	assertEqual(0, #triangles)
	assertEqual(nil, Mesh.bounds(triangles))
end)

test("a zero scale gives no triangles", function()
	assertEqual(0, #Mesh.ofTree(tree("return box{ transform = { scale = { 1, 0, 1 } } }")))
end)

test("clipping cuts geometry below the ground away", function()
	local triangles = Mesh.clip(Mesh.ofTree(tree("return box{ size = { 1, 1, 2 }, transform = { move = { 0, 0, -1 } } }")))
	assertBounds({ 0, 0, 0, 1, 1, 1 }, Mesh.bounds(triangles))
	assertOutward(triangles)
	for _, v in ipairs(triangles) do
		assertTrue(v.z >= 0, "vertex below ground")
	end
end)

test("clipping keeps a sphere's top half, its widest ring on the ground", function()
	local triangles = Mesh.clip(Mesh.ofTree(tree("return sphere{ radius = 1 }")))
	assertBounds({ -1, -1, 0, 1, 1, 1 }, Mesh.bounds(triangles))
	assertOutward(triangles)
end)

test("geometry wholly below the ground clips to nothing", function()
	assertEqual(0, #Mesh.clip(Mesh.ofTree(tree("return box{ transform = { move = { 0, 0, -3 } } }"))))
end)

test("the footprint is the ground bounds rounded up to whole tiles", function()
	local f = Footprint.of(boundsOf("return box{ size = { 0.1, 2.5, 1 }, transform = { move = { 1, -1, 0 } } }"))
	assertEqual(1, f.width)
	assertEqual(3, f.depth)
	assertNear(1, f.x)
	assertNear(-1, f.y)
end)

test("a footprint exactly whole tiles wide does not grow from rounding error", function()
	local f = Footprint.of(boundsOf("return box{ size = { 1, 1, 1 }, transform = { scale = { 3, 2, 1 }, rotate = { 0, 0, 360 } } }"))
	assertEqual(3, f.width)
	assertEqual(2, f.depth)
end)

test("no geometry has no footprint", function()
	assertEqual(nil, Footprint.of(nil))
end)

test("turning to a facing turns the geometry clockwise about its footprint, as the baker's models turn", function()
	-- A 1 x 0.5 box in the north-west corner of a 3 x 2 footprint.
	local triangles = Mesh.ofTree(tree("return box{ size = { 1, 0.5, 1 } }"))
	local east, w, d = Mesh.turn(triangles, 3, 2, "E")
	assertEqual(2, w)
	assertEqual(3, d)
	-- The north edge becomes the east edge.
	assertBounds({ 1.5, 0, 0, 2, 1, 1 }, Mesh.bounds(east))
	assertOutward(east)
	local south = Mesh.turn(triangles, 3, 2, "S")
	assertBounds({ 2, 1.5, 0, 3, 2, 1 }, Mesh.bounds(south))
	local north = Mesh.turn(triangles, 3, 2, "N")
	assertBounds({ 0, 0, 0, 1, 0.5, 1 }, Mesh.bounds(north))
end)

test("a cylinder stands on the ground about its axis, its height up, and faces outward", function()
	local triangles = Mesh.ofTree(tree("return cylinder{ radius = 1.5, height = 2, segments = 12 }"))
	assertBounds({ -1.5, -1.5, 0, 1.5, 1.5, 2 }, Mesh.bounds(triangles))
	assertOutward(triangles)
end)

test("a cone stands on the ground about its axis, narrowing to a point at its height, and faces outward", function()
	local triangles = Mesh.ofTree(tree("return cone{ radius = 1, height = 3, segments = 8 }"))
	assertBounds({ -1, -1, 0, 1, 1, 3 }, Mesh.bounds(triangles))
	assertOutward(triangles)
end)

test("a wedge spans its size from the origin, sloping from full height on the west to the ground on the east, and faces outward", function()
	local triangles = Mesh.ofTree(tree("return wedge{ size = { 2, 1, 3 } }"))
	assertBounds({ 0, 0, 0, 2, 1, 3 }, Mesh.bounds(triangles))
	assertOutward(triangles)
	for _, v in ipairs(triangles) do
		assertTrue(v.z <= 3 * (1 - v.x / 2) + 1e-9, "vertex above the slope")
	end
end)

test("a sphere's segments set how finely it is cut; too many is an error, not a hang", function()
	local coarse = Mesh.ofTree(tree("return sphere{ radius = 1, segments = 8 }"))
	assertTrue(#coarse < #Mesh.ofTree(tree("return sphere{ radius = 1 }")), "expected fewer triangles")
	assertBounds({ -1, -1, -1, 1, 1, 1 }, Mesh.bounds(coarse))
	assertOutward(coarse)
	local _, message = Sandbox.run("return sphere{ segments = 100000 }", "design")
	assertTrue(message and message:find("segments", 1, true), tostring(message))
end)

-- Materials (docs/CONTEXT.md "Material", "Texture variant").

test("a node's material and texture transform reach its children's vertices unless a child sets its own", function()
	local parts = Mesh.parts(tree([[
return group{ material = { name = "stone", variant = "brick", scale = 2, rotation = 30 },
	box{},
	box{ material = { name = "plank", variant = "shingles" } },
}]]))
	assertEqual(2, #parts)
	for _, v in ipairs(parts[1]) do
		assertEqual("stone", v.material)
		assertEqual("brick", v.texture.variant)
		assertEqual(2, v.texture.scale)
		assertEqual(30, v.texture.rotation)
	end
	for _, v in ipairs(parts[2]) do
		assertEqual("plank", v.material)
		assertEqual("shingles", v.texture.variant)
		assertEqual(1, v.texture.scale)
		assertEqual(0, v.texture.rotation)
	end
end)

test("an operation's solid is made of its material, inherited from above", function()
	local parts = Mesh.parts(tree([[
return group{ material = { name = "stone", variant = "rough" },
	extrude{ height = 1, shape{ points = { { 0, 0 }, { 1, 0 }, { 1, 1 } } } },
}]]))
	assertEqual(1, #parts)
	assertTrue(#parts[1] > 0, "expected triangles")
	for _, v in ipairs(parts[1]) do
		assertEqual("stone", v.material)
		assertEqual("rough", v.texture.variant)
	end
end)

test("a node without a material anywhere above it leaves its vertices without one", function()
	for _, v in ipairs(Mesh.ofTree(tree("return group{ box{} }"))) do
		assertEqual(nil, v.material)
		assertEqual(nil, v.texture)
	end
end)

test("stone geometry takes stone's colour and plank plank's, which is the default colour", function()
	local parts = Mesh.parts(tree([[
return group{ box{ material = { name = "stone" } }, box{ material = { name = "plank" } } }]]))
	local stone, plank = parts[1][1], parts[2][1]
	assertEqual(Mesh.MATERIAL_COLORS.stone[1], stone.r)
	assertEqual(Mesh.MATERIAL_COLORS.stone[3], stone.b)
	assertEqual(Mesh.DEFAULT_COLOR[2], plank.g)
	assertTrue(math.abs(stone.r - plank.r) > 0.1, "stone and plank should differ in colour")
end)

-- Colours (docs/CONTEXT.md "Team palette").

test("a node's RGB colour paints its children unless a child sets its own, over its material's colour", function()
	local parts = Mesh.parts(tree([[
return group{ color = { 0.1, 0.2, 0.3 },
	box{ material = { name = "stone" } },
	box{ color = { 0.9, 0.8, 0.7 } },
}]]))
	for _, v in ipairs(parts[1]) do
		assertEqual(0.1, v.r)
		assertEqual(0.3, v.b)
		assertEqual("stone", v.material, "the colour tints the material")
		assertEqual(nil, v.slot)
	end
	for _, v in ipairs(parts[2]) do
		assertEqual(0.8, v.g)
	end
end)

test("a team slot colour marks its vertices with the slot, drawn in the default palette", function()
	local Palette = require("src.game.palette")
	local tris = Mesh.ofTree(tree([[
return group{ box{ color = "primary" }, box{ transform = { move = { 2, 0, 0 } } } }]]))
	local painted, plain = 0, 0
	for _, v in ipairs(tris) do
		if v.x < 1.5 then
			painted = painted + 1
			assertEqual("primary", v.slot)
			assertEqual(Palette.DEFAULT.primary[1], v.r)
		else
			plain = plain + 1
			assertEqual(nil, v.slot)
		end
	end
	assertTrue(painted > 0 and plain > 0, "fixture: both boxes meshed")
end)

test("a slot survives transforms, turns and the ground clip", function()
	local tris = Mesh.ofTree(tree([[return box{ color = "secondaryLight", transform = { move = { 0, 0, -0.5 }, rotate = { 0, 0, 30 } } }]]))
	local turned = Mesh.turn(Mesh.clip(tris), 2, 2, "E")
	assertTrue(#turned > 0)
	for _, v in ipairs(turned) do
		assertEqual("secondaryLight", v.slot)
	end
end)
