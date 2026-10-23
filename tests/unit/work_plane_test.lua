-- Work planes (src/game/builder/work_plane.lua): the plane shapes are
-- drawn on -- the ground, an axis plane at a height or an adopted face --
-- and where a ray from the camera meets it, in the plane's own 2D
-- coordinates, snapped to its grid.
local WorkPlane = require("src.game.builder.work_plane")
local Sandbox = require("src.game.script.sandbox")
local Pick = require("src.game.geometry.pick")
local Primitives = require("src.game.geometry.primitives")

test("a ray meets the ground at the snapped point under it, in plane and design coordinates", function()
	local plane = WorkPlane.ground()
	local at, point = WorkPlane.hit(plane, { 1.3, 2.1, 5 }, { 0, 0, -1 })
	assertEqual(1.25, at[1])
	assertEqual(2, at[2])
	assertEqual("1.25 2 0", table.concat(point, " "))
	local free = WorkPlane.hit(plane, { 1.3, 2.1, 5 }, { 0, 0, -1 }, true)
	assertNear(1.3, free[1], 1e-9)
	assertEqual(nil, (WorkPlane.hit(plane, { 0, 0, 5 }, { 0, 0, 1 })), "pointing away misses")
	assertEqual(nil, (WorkPlane.hit(plane, { 0, 0, 5 }, { 1, 0, 0 })), "parallel misses")
end)

test("XY, XZ and YZ planes sit at a height along their missing axis", function()
	local xy = WorkPlane.axis("XY", 1.5)
	local _, p = WorkPlane.hit(xy, { 1, 1, 9 }, { 0, 0, -1 })
	assertEqual("1 1 1.5", table.concat(p, " "))
	local xz = WorkPlane.axis("XZ", 2)
	local at, q = WorkPlane.hit(xz, { 0.6, 9, 1.1 }, { 0, -1, 0 })
	assertEqual("0.5 1", table.concat(at, " "), "plane coordinates are x and z")
	assertEqual("0.5 2 1", table.concat(q, " "))
	local yz = WorkPlane.axis("YZ", -1)
	local _, r = WorkPlane.hit(yz, { 5, 0.5, 0.5 }, { -1, 0, 0 })
	assertEqual("-1 0.5 0.5", table.concat(r, " "))
end)

-- The face of a 2 x 2 x 1 box at the origin a ray from `origin` along
-- `dir` meets, adopted as the work plane.
local function adopt(origin, dir)
	local targets = { { id = "box1", triangles = Primitives.box({ 2, 2, 1 }, { 1, 1, 1 }) } }
	local id, t, normal = Pick.at(targets, origin, dir)
	assertEqual("box1", id)
	local hit = { origin[1] + dir[1] * t, origin[2] + dir[2] * t, origin[3] + dir[3] * t }
	return WorkPlane.face(hit, normal)
end

test("a clicked face becomes the work plane, its grid lined up with the design's", function()
	local top = adopt({ 0.7, 0.7, 5 }, { 0, 0, -1 })
	assertEqual("0 0 1", table.concat(top.origin, " "))
	assertEqual("1 0 0", table.concat(top.u, " "))
	assertEqual("0 1 0", table.concat(top.v, " "))
	-- The north face (y = 0) faces -y: plane coordinates run east and up.
	local north = adopt({ 0.7, -5, 0.5 }, { 0, 1, 0 })
	local at, p = WorkPlane.hit(north, { 0.6, -5, 0.4 }, { 0, 1, 0 })
	assertEqual("0.5 0.5", table.concat(at, " "))
	assertEqual("0.5 0 0.5", table.concat(p, " "))
	-- East face (x = 2): runs south and up, origin on the face.
	local east = adopt({ 5, 0.5, 0.5 }, { -1, 0, 0 })
	assertEqual("2 0 0", table.concat(east.origin, " "))
	assertEqual("0 1 0", table.concat(east.u, " "))
	assertEqual("0 0 1", table.concat(east.v, " "))
end)

test("each shape in a tree comes with its plane in design space, every transform above applied", function()
	local root = assert(Sandbox.run([[
return group{ id = "root", transform = { move = { 1, 2, 0 } },
	shape{ id = "s", points = { { 0, 0 }, { 1, 0 }, { 1, 1 } }, transform = { scale = 2 },
		plane = { origin = { 0, 0, 0.5 }, u = { 1, 0, 0 }, v = { 0, 1, 0 } } },
	box{ id = "b" },
}
]], "design")).root
	local shapes = WorkPlane.shapes(root)
	assertEqual(1, #shapes)
	local s = shapes[1]
	assertEqual("s", s.id)
	assertEqual("1 2 1", table.concat(s.plane.origin, " "))
	assertEqual("2 0 0", table.concat(s.plane.u, " "))
	-- Its outline in design space: (1, 1) on the plane is (3, 4, 1).
	assertEqual("3 4 1", table.concat(s.outline[3], " "))
	-- And a ray hitting it gives back the shape's own coordinates.
	local at = WorkPlane.hit(s.plane, { 3, 4, 5 }, { 0, 0, -1 })
	assertEqual("1 1", table.concat(at, " "))
end)

test("the grid drawn on a plane: quarter-tile lines round a point, every whole tile major", function()
	local lines = WorkPlane.grid(WorkPlane.axis("XY", 1), { 0.3, 0 }, 1)
	-- From -0.75 to 1.25 in a (the grid point nearest 0.3 is 0.25), -1 to 1 in b:
	-- 9 lines each way.
	assertEqual(18, #lines)
	local majors = 0
	for _, l in ipairs(lines) do
		assertEqual(1, l[1][3], "on the plane")
		majors = majors + (l.major and 1 or 0)
	end
	-- a = 0 and 1; b = -1, 0 and 1.
	assertEqual(5, majors)
end)

test("each path in a tree comes with its points in design space, every transform above applied", function()
	local root = assert(Sandbox.run([[
return group{ id = "root", transform = { move = { 1, 0, 0 } },
	sweep{ id = "w", shape{ points = { { 0, 0 }, { 1, 0 }, { 1, 1 } } },
		path{ id = "p", curve = "line", points = { { 0, 0 }, { 2, 0 } }, transform = { move = { 0, 0, 3 } } } },
}
]], "design")).root
	local paths = WorkPlane.paths(root)
	assertEqual(1, #paths)
	assertEqual("p", paths[1].id)
	assertEqual("path", paths[1].node.kind)
	assertEqual("1 0 3", table.concat(paths[1].points[1], " "))
	assertEqual("3 0 3", table.concat(paths[1].points[2], " "))
end)
