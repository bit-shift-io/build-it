-- Work planes (docs/CONTEXT.md "Work plane"): the plane the builder draws
-- shapes on, and where the pointer's ray meets it. Pure; plain LuaJIT.
--
--   plane = { origin = { x, y, z }, u = { x, y, z }, v = { x, y, z } }
--
-- in design space (tiles; x east, y south, z up). A point (a, b) in the
-- plane's own 2D coordinates sits at origin + a * u + b * v; its normal is
-- u x v. A shape (src/game/geometry/shape2d.lua) keeps its points in these
-- coordinates and the plane beside them, so operations know its axis.
local Mesh = require("src.game.geometry.mesh")
local Shape2d = require("src.game.geometry.shape2d")
local Path = require("src.game.geometry.path")

local WorkPlane = {}

-- The grid the plane snaps to, in tiles.
WorkPlane.SNAP = 0.25

local function dot(a, b)
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

local function cross(a, b)
	return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end

local function snapped(x)
	return math.floor(x / WorkPlane.SNAP + 0.5) * WorkPlane.SNAP
end

-- The ground, z = 0, its coordinates design x and y.
function WorkPlane.ground()
	return { origin = { 0, 0, 0 }, u = { 1, 0, 0 }, v = { 0, 1, 0 } }
end

-- The axis planes by name: which axes their coordinates follow, and the
-- one their height is along.
local AXES = {
	XY = { u = { 1, 0, 0 }, v = { 0, 1, 0 }, along = 3 },
	XZ = { u = { 1, 0, 0 }, v = { 0, 0, 1 }, along = 2 },
	YZ = { u = { 0, 1, 0 }, v = { 0, 0, 1 }, along = 1 },
}
WorkPlane.AXES = { "XY", "XZ", "YZ" }

-- Axis plane `name` ("XY", "XZ" or "YZ") at `height` tiles along the axis
-- it leaves out.
function WorkPlane.axis(name, height)
	local axis = assert(AXES[name], "unknown axis plane " .. tostring(name))
	local origin = { 0, 0, 0 }
	origin[axis.along] = height
	return { origin = origin, u = { axis.u[1], axis.u[2], axis.u[3] }, v = { axis.v[1], axis.v[2], axis.v[3] } }
end

local function unit(a)
	local len = math.sqrt(dot(a, a))
	return { a[1] / len + 0, a[2] / len + 0, a[3] / len + 0 }
end

-- The plane of a face through design-space `point` facing `normal` (a
-- clicked face, Pick.at): its origin the plane's point nearest the
-- design's origin and u level, so an upright face's grid lines up with
-- the design's and runs up the face, and a flat face's runs with x and y.
function WorkPlane.face(point, normal)
	local n = unit(normal)
	local level = cross({ 0, 0, 1 }, n)
	local u = dot(level, level) > 1e-12 and unit(level) or { 1, 0, 0 }
	local v = unit(cross(n, u))
	local d = dot(point, n)
	return { origin = { d * n[1] + 0, d * n[2] + 0, d * n[3] + 0 }, u = u, v = v }
end

-- Design-space point (a, b) of `plane`: { x, y, z }.
function WorkPlane.at(plane, a, b)
	local o, u, v = plane.origin, plane.u, plane.v
	return { o[1] + a * u[1] + b * v[1], o[2] + a * u[2] + b * v[2], o[3] + a * u[3] + b * v[3] }
end

-- Where the ray from `origin` along `dir` (design space) meets `plane`:
-- its plane coordinates { a, b }, snapped to the grid unless `free`, and
-- that design-space point; nil when the ray runs parallel or away.
function WorkPlane.hit(plane, origin, dir, free)
	local u, v = plane.u, plane.v
	local n = cross(u, v)
	local facing = dot(dir, n)
	if facing == 0 then
		return nil
	end
	local o = plane.origin
	local rel = { origin[1] - o[1], origin[2] - o[2], origin[3] - o[3] }
	local t = -dot(rel, n) / facing
	if t < 0 then
		return nil
	end
	local p = { rel[1] + dir[1] * t, rel[2] + dir[2] * t, rel[3] + dir[3] * t }
	-- Solve p = a u + b v (u and v need not be unit or square).
	local uu, uv, vv = dot(u, u), dot(u, v), dot(v, v)
	local pu, pv = dot(p, u), dot(p, v)
	local det = uu * vv - uv * uv
	local a, b = (pu * vv - pv * uv) / det, (pv * uu - pu * uv) / det
	if not free then
		a, b = snapped(a), snapped(b)
	end
	return { a, b }, WorkPlane.at(plane, a, b)
end

-- The grid lines of `plane` within `extent` tiles of the grid point
-- nearest plane point `centre` ({ a, b }): { { from, to, major }, ... }
-- with from and to design-space { x, y, z }; major on whole tiles.
function WorkPlane.grid(plane, centre, extent)
	local ca, cb = snapped(centre[1]), snapped(centre[2])
	local steps = math.floor(extent / WorkPlane.SNAP + 0.5)
	local lines = {}
	for i = -steps, steps do
		local a, b = ca + i * WorkPlane.SNAP, cb + i * WorkPlane.SNAP
		lines[#lines + 1] = {
			WorkPlane.at(plane, a, cb - extent),
			WorkPlane.at(plane, a, cb + extent),
			major = a % 1 == 0,
		}
		lines[#lines + 1] = {
			WorkPlane.at(plane, ca - extent, b),
			WorkPlane.at(plane, ca + extent, b),
			major = b % 1 == 0,
		}
	end
	return lines
end

-- Point p with `chain` of node transforms applied, innermost first.
local function through(chain, p)
	local x, y, z = p[1], p[2], p[3]
	for i = #chain, 1, -1 do
		x, y, z = Mesh.transformPoint(chain[i], x, y, z)
	end
	return { x + 0, y + 0, z + 0 }
end

-- `plane` carried through `chain`: its origin and the tips of u and v
-- moved, so a scaled or turned shape keeps its own coordinates.
local function carried(chain, plane)
	local o = through(chain, plane.origin)
	local function axis(d)
		local tip = through(chain, { plane.origin[1] + d[1], plane.origin[2] + d[2], plane.origin[3] + d[3] })
		return { tip[1] - o[1], tip[2] - o[2], tip[3] - o[3] }
	end
	return { origin = o, u = axis(plane.u), v = axis(plane.v) }
end

local function collect(node, chain, out, paths)
	chain[#chain + 1] = node.transform or {}
	if node.kind == "path" and paths then
		local points = {}
		for i, p in ipairs(Path.points(node) or {}) do
			points[i] = through(chain, p)
		end
		out[#out + 1] = { id = node.id, node = node, points = points }
	elseif node.kind == "shape" and not paths then
		local plane = carried(chain, node.plane)
		local outline = {}
		for i, p in ipairs(Shape2d.outline(node.points) or {}) do
			outline[i] = WorkPlane.at(plane, p[1], p[2])
		end
		out[#out + 1] = { id = node.id, node = node, plane = plane, outline = outline }
	elseif node.kind ~= "prefab" then
		for _, child in ipairs(node.children or {}) do
			collect(child, chain, out, paths)
		end
	end
	chain[#chain] = nil
	return out
end

-- Every shape in the tree under `root` (prefab instances' insides left
-- out), in tree order: { { id, node, plane, outline }, ... } with its plane
-- carried into design space through every transform above it, and its
-- outline (Shape2d.outline) as design-space corners { x, y, z }.
function WorkPlane.shapes(root)
	return collect(root, {}, {})
end

-- Every path in the tree under `root` (prefab instances' insides left
-- out), in tree order: { { id, node, points }, ... } with its points
-- (Path.points) carried into design space through every transform above
-- it and its own.
function WorkPlane.paths(root)
	return collect(root, {}, {}, true)
end

return WorkPlane
