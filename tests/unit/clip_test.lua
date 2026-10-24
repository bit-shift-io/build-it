-- Cutaway geometry (docs/CONTEXT.md "Cutaway"): a triangle list clipped at
-- a z plane keeps only what lies at or below it.
local Clip = require("src.game.geometry.clip")
local Mesh = require("src.game.geometry.mesh")
local Primitives = require("src.game.geometry.primitives")

test("a box clipped at mid-height is a box half as tall", function()
	local box = Primitives.box({ 2, 1, 1 }, { 1, 1, 1 })
	local b = Mesh.bounds(Clip.below(box, 0.5))
	assertEqual(0, b.minX)
	assertEqual(2, b.maxX)
	assertEqual(1, b.maxY)
	assertEqual(0, b.minZ)
	assertEqual(0.5, b.maxZ)
end)

local function v(x, y, z)
	return { x = x, y = y, z = z, nx = 0, ny = -1, nz = 0, r = 0.2, g = 0.4, b = 0.6, material = "stone", slot = "primary" }
end

test("a triangle wholly above the plane is dropped", function()
	assertEqual(0, #Clip.below({ v(0, 0, 1), v(1, 0, 1), v(0, 0, 2) }, 0.5))
end)

test("a triangle wholly below the plane is kept as it is", function()
	local tri = { v(0, 0, 0), v(1, 0, 0), v(0, 0, 0.25) }
	local out = Clip.below(tri, 0.5)
	assertEqual(3, #out)
	assertEqual(tri[3], out[3])
end)

test("a triangle straddling the plane is split at it, keeping its look", function()
	-- One corner below, two above: a smaller triangle, cut along z = 0.5.
	local out = Clip.below({ v(0, 0, 0), v(2, 0, 1), v(0, 0, 1) }, 0.5)
	assertEqual(3, #out)
	assertEqual(0.5, out[2].z)
	assertEqual(1, out[2].x)
	assertEqual(0.5, out[3].z)
	assertEqual(0, out[3].x)
	assertEqual("stone", out[2].material)
	assertEqual("primary", out[3].slot)
	assertEqual(-1, out[2].ny)
	-- Two corners below, one above: a quad, as two triangles.
	out = Clip.below({ v(0, 0, 0), v(2, 0, 0), v(0, 0, 1) }, 0.5)
	assertEqual(6, #out)
	for _, c in ipairs(out) do
		assertTrue(c.z <= 0.5, "nothing above the cut")
	end
end)
