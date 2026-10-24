-- Mesh.yaw (src/game/geometry/mesh.lua): a triangle list turned by any angle
-- about its footprint centre, clockwise seen from above, as the baker turns
-- a figure to each of its 8 facings.
local Sandbox = require("src.game.script.sandbox")
local Mesh = require("src.game.geometry.mesh")

-- A small box off the centre of a 1x1 footprint, so a turn moves it.
local function triangles()
	return Mesh.ofTree(assert(Sandbox.run("return box{ size = { 0.3, 0.2, 0.5 }, move = { 0.1, 0.05, 0 } }", "design")).root)
end

local FIELDS = { "x", "y", "z", "nx", "ny", "nz" }

local function assertSameVertices(expected, actual)
	assertEqual(#expected, #actual)
	for i, v in ipairs(expected) do
		for _, f in ipairs(FIELDS) do
			assertNear(v[f], actual[i][f], 1e-9, "vertex " .. i .. " " .. f)
		end
		assertEqual(v.r, actual[i].r)
		assertEqual(v.material, actual[i].material)
		assertEqual(v.slot, actual[i].slot)
	end
end

test("a 90 degree yaw on a 1x1 footprint turns the mesh as the quarter turn to E does", function()
	local tris = triangles()
	assertSameVertices((Mesh.turn(tris, 1, 1, "E")), Mesh.yaw(tris, 1, 1, 90))
end)

test("a 45 degree yaw keeps normals unit length and the mesh centred on the footprint", function()
	local tris = triangles()
	local turned = Mesh.yaw(tris, 1, 1, 45)
	for i, v in ipairs(turned) do
		assertNear(1, math.sqrt(v.nx * v.nx + v.ny * v.ny + v.nz * v.nz), 1e-9, "normal " .. i)
		-- Distance from the footprint centre is kept.
		local a, b = tris[i], v
		assertNear((a.x - 0.5) ^ 2 + (a.y - 0.5) ^ 2, (b.x - 0.5) ^ 2 + (b.y - 0.5) ^ 2, 1e-9, "radius " .. i)
	end
	-- Clockwise from above: a point due east of the centre moves south-east.
	local east = Mesh.yaw({ { x = 1, y = 0.5, z = 0, nx = 1, ny = 0, nz = 0 } }, 1, 1, 45)[1]
	assertNear(0.5 + math.sqrt(0.125), east.x, 1e-9)
	assertNear(0.5 + math.sqrt(0.125), east.y, 1e-9)
end)

test("a 360 degree yaw leaves the mesh as it was", function()
	local tris = triangles()
	assertSameVertices(tris, Mesh.yaw(tris, 1, 1, 360))
end)
