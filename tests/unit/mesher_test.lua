local Model = require("src.game.blocks.model")
local Mesher = require("src.game.blocks.mesher")

local GREY = { 0.5, 0.5, 0.5 }

local function modelOf(cells)
	local m = Model.new(4)
	for _, c in ipairs(cells) do
		c.color = c.color or GREY
		Model.addCell(m, c)
	end
	return m
end

local function triangleCount(vertices)
	return #vertices / 3
end

local function assertWoundOutward(verts)
	for i = 1, #verts, 3 do
		local a, b, c = verts[i], verts[i + 1], verts[i + 2]
		local ux, uy, uz = b.x - a.x, b.y - a.y, b.z - a.z
		local vx, vy, vz = c.x - a.x, c.y - a.y, c.z - a.z
		local cx, cy, cz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
		assertTrue(cx * a.nx + cy * a.ny + cz * a.nz > 0, "triangle " .. ((i + 2) / 3) .. " is wound inward")
		assertNear(1, a.nx * a.nx + a.ny * a.ny + a.nz * a.nz)
	end
end

test("Mesher.mesh emits 12 triangles for a lone box, wound outward with unit normals", function()
	local verts = Mesher.mesh(modelOf({ { x = 2, y = 3, z = 1, color = { 1, 0.5, 0.25 } } }))
	assertEqual(36, #verts)
	assertWoundOutward(verts)
	for i = 1, #verts, 3 do
		local a, b, c = verts[i], verts[i + 1], verts[i + 2]
		assertEqual(1, a.r)
		assertEqual(0.5, a.g)
		assertEqual(0.25, a.b)
		for _, v in ipairs({ a, b, c }) do
			assertTrue(v.x >= 2 and v.x <= 3 and v.y >= 3 and v.y <= 4 and v.z >= 1 and v.z <= 2, "vertex outside its cell")
		end
	end
end)

test("Mesher.mesh drops the faces two adjacent boxes share", function()
	local verts = Mesher.mesh(modelOf({ { x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 } }))
	assertEqual(20, triangleCount(verts))
	for i = 1, #verts, 3 do
		local onSharedPlane = verts[i].x == 1 and verts[i + 1].x == 1 and verts[i + 2].x == 1
		assertFalse(onSharedPlane, "expected no triangle on the shared x = 1 plane")
	end
end)

test("Mesher.mesh culls a box's face covered by a box stacked on it", function()
	local verts = Mesher.mesh(modelOf({ { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 1 } }))
	assertEqual(20, triangleCount(verts))
end)

test("Mesher.mesh emits 8 outward triangles for a lone slope in every dir", function()
	for _, dir in ipairs({ "N", "E", "S", "W" }) do
		local verts = Mesher.mesh(modelOf({ { x = 1, y = 1, z = 0, shape = "slope", dir = dir } }))
		assertEqual(8, triangleCount(verts), "slope " .. dir)
		assertWoundOutward(verts)
	end
end)

test("Mesher.mesh gives a slope's sloped face a normal looking up and toward its dir", function()
	local verts = Mesher.mesh(modelOf({ { x = 0, y = 0, z = 0, shape = "slope", dir = "S" } }))
	local found = false
	for _, v in ipairs(verts) do
		if v.ny > 0 and v.nz > 0 then
			found = true
			assertNear(math.sqrt(0.5), v.ny)
			assertNear(math.sqrt(0.5), v.nz)
		end
	end
	assertTrue(found, "expected a south-and-up facing triangle")
end)

test("Mesher.mesh culls against a slope's full bottom and back but not its ends", function()
	-- Box under a slope: the box top hides under the slope's full bottom.
	local stacked = Mesher.mesh(modelOf({ { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 1, shape = "slope", dir = "S" } }))
	assertEqual(10 + 6, triangleCount(stacked))

	-- Box east of a south slope: the slope's end hides, the box's west face shows.
	local beside = Mesher.mesh(modelOf({ { x = 0, y = 0, z = 0, shape = "slope", dir = "S" }, { x = 1, y = 0, z = 0 } }))
	assertEqual(7 + 12, triangleCount(beside))
end)

test("Mesher.mesh culls matching slope ends in a roof row, not mismatched ones", function()
	local row = Mesher.mesh(modelOf({
		{ x = 0, y = 0, z = 0, shape = "slope", dir = "N" },
		{ x = 1, y = 0, z = 0, shape = "slope", dir = "N" },
	}))
	assertEqual(7 + 7, triangleCount(row))

	local mismatched = Mesher.mesh(modelOf({
		{ x = 0, y = 0, z = 0, shape = "slope", dir = "N" },
		{ x = 1, y = 0, z = 0, shape = "slope", dir = "S" },
	}))
	assertEqual(8 + 8, triangleCount(mismatched))
end)

test("every vertex carries its cell's material, nil when it has none", function()
	local verts = Mesher.mesh(modelOf({ { x = 0, y = 0, z = 0, material = "stone" }, { x = 3, y = 0, z = 0 } }))
	for _, v in ipairs(verts) do
		assertEqual(v.x <= 1 and "stone" or nil, v.material)
	end
end)
