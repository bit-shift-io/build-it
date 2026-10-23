-- Move, rotate and scale in the builder (docs/CONTEXT.md "Builder"): how
-- far a drag goes, from rays through the builder camera, and what it does
-- to the selected nodes' transforms. Pure; plain LuaJIT. Lengths in tiles,
-- in the design's own space (x east, y south, z up), angles in degrees.
--
-- A drag starts with Transform.start at the selection's centre and the
-- pointer's ray at that moment; each later ray gives the drag's amount
-- (Transform.amount), which Transform.apply turns into node transforms.
local Scene = require("src.game.builder.scene")
local Mesh = require("src.game.geometry.mesh")

local Transform = {}

-- Steps the amounts snap to unless freed: a quarter tile, 15 degrees and a
-- tenth of the scale.
Transform.SNAP = { move = 0.25, rotate = 15, scale = 0.1 }

Transform.AXES = { x = { 1, 0, 0 }, y = { 0, 1, 0 }, z = { 0, 0, 1 } }

local function sub(a, b)
	return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end

local function dot(a, b)
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

local function snap(v, step)
	return math.floor(v / step + 0.5) * step
end

-- How far along the line through `point` along unit `axis` the ray
-- (origin, direction) passes nearest; nil when they run parallel.
local function onAxis(point, axis, origin, direction)
	local w = sub(point, origin)
	local b, c = dot(axis, direction), dot(direction, direction)
	local denom = c - b * b
	if math.abs(denom) < 1e-12 * c then
		return nil
	end
	return (b * dot(direction, w) - c * dot(axis, w)) / denom
end

-- Where the ray (origin, direction) meets the plane through `point` with
-- normal `normal`; nil when it runs along the plane.
local function onPlane(point, normal, origin, direction)
	local along = dot(normal, direction)
	if math.abs(along) < 1e-9 then
		return nil
	end
	local t = dot(normal, sub(point, origin)) / along
	return { origin[1] + direction[1] * t, origin[2] + direction[2] * t, origin[3] + direction[3] * t }
end

-- A drag of `mode` ("move", "rotate" or "scale") about `centre`, begun
-- with the pointer's ray (origin, direction). Its axis ("x", "y", "z" or
-- nil for none) may be set at any time.
function Transform.start(mode, centre, origin, direction)
	return { mode = mode, centre = centre, axis = nil, from = { origin, direction } }
end

local function cross(a, b)
	return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end

-- Where the drag's first ray and the ray (origin, direction) meet the
-- plane through the centre with `normal`; nil when either runs along it.
local function planeHits(drag, normal, origin, direction)
	local h0 = onPlane(drag.centre, normal, drag.from[1], drag.from[2])
	local h1 = onPlane(drag.centre, normal, origin, direction)
	if h0 and h1 then
		return h0, h1
	end
end

local AMOUNTS = {}

-- Along the axis, or with none on the level plane through the centre.
function AMOUNTS.move(drag, origin, direction, free)
	local axis = Transform.AXES[drag.axis]
	local step = not free and Transform.SNAP.move
	if not axis then
		local h0, h1 = planeHits(drag, Transform.AXES.z, origin, direction)
		if not h0 then
			return nil
		end
		local d = sub(h1, h0)
		return { step and snap(d[1], step) or d[1], step and snap(d[2], step) or d[2], 0 }
	end
	local s0 = onAxis(drag.centre, axis, drag.from[1], drag.from[2])
	local s1 = onAxis(drag.centre, axis, origin, direction)
	if not s0 or not s1 then
		return nil
	end
	local d = step and snap(s1 - s0, step) or s1 - s0
	return { axis[1] * d, axis[2] * d, axis[3] * d }
end

-- The angle swept about the axis (z when none), read on the plane through
-- the centre square to it; right-handed.
function AMOUNTS.rotate(drag, origin, direction, free)
	local axis = Transform.AXES[drag.axis or "z"]
	local h0, h1 = planeHits(drag, axis, origin, direction)
	if not h0 then
		return nil
	end
	local v0, v1 = sub(h0, drag.centre), sub(h1, drag.centre)
	local degrees = math.deg(math.atan2(dot(axis, cross(v0, v1)), dot(v0, v1)))
	return free and degrees or snap(degrees, Transform.SNAP.rotate)
end

-- The factor the pointer's distance from the centre has grown by since the
-- drag began: along the axis, or with none on the level plane through the
-- centre. Never below the snap step (or MIN_FREE_SCALE when free), so a
-- scale never flattens or mirrors.
local MIN_FREE_SCALE = 0.01
function AMOUNTS.scale(drag, origin, direction, free)
	local axis = Transform.AXES[drag.axis]
	local r0, r1
	if axis then
		r0 = onAxis(drag.centre, axis, drag.from[1], drag.from[2])
		r1 = onAxis(drag.centre, axis, origin, direction)
	else
		local h0, h1 = planeHits(drag, Transform.AXES.z, origin, direction)
		if h0 then
			local v0, v1 = sub(h0, drag.centre), sub(h1, drag.centre)
			r0, r1 = math.sqrt(dot(v0, v0)), math.sqrt(dot(v1, v1))
		end
	end
	if not r0 or not r1 or math.abs(r0) < 1e-6 then
		return nil
	end
	local factor = r1 / r0
	if free then
		return math.max(MIN_FREE_SCALE, factor)
	end
	return math.max(Transform.SNAP.scale, snap(factor, Transform.SNAP.scale))
end

-- How far `drag` has gone with the pointer's ray now (origin, direction),
-- snapped unless `free`: a move's { dx, dy, dz }, a rotate's degrees, a
-- scale's factor; nil
-- when the ray gives no answer (it runs along the plane or axis).
function Transform.amount(drag, origin, direction, free)
	return AMOUNTS[drag.mode](drag, origin, direction, free)
end

-- 3x3 matrices, rows first, and affine maps { m = <matrix>, t = { x, y, z } }.

local function mul(a, b)
	local out = {}
	for r = 1, 3 do
		out[r] = {}
		for c = 1, 3 do
			out[r][c] = a[r][1] * b[1][c] + a[r][2] * b[2][c] + a[r][3] * b[3][c]
		end
	end
	return out
end

local function apply3(m, v)
	return { dot(m[1], v), dot(m[2], v), dot(m[3], v) }
end

local function inverse(m)
	local a, b, c = m[1][1], m[1][2], m[1][3]
	local d, e, f = m[2][1], m[2][2], m[2][3]
	local g, h, i = m[3][1], m[3][2], m[3][3]
	local A, B, C = e * i - f * h, -(d * i - f * g), d * h - e * g
	local det = a * A + b * B + c * C
	return {
		{ A / det, -(b * i - c * h) / det, (b * f - c * e) / det },
		{ B / det, (a * i - c * g) / det, -(a * f - c * d) / det },
		{ C / det, -(a * h - b * g) / det, (a * e - b * d) / det },
	}
end

local function diagonal(v)
	return { { v[1], 0, 0 }, { 0, v[2], 0 }, { 0, 0, v[3] } }
end

-- The turn of `rotate` (degrees about x, then y, then z), as Mesh does it.
local function rotationOf(rotate)
	local x, y, z = math.rad(rotate[1]), math.rad(rotate[2]), math.rad(rotate[3])
	local rx = { { 1, 0, 0 }, { 0, math.cos(x), -math.sin(x) }, { 0, math.sin(x), math.cos(x) } }
	local ry = { { math.cos(y), 0, math.sin(y) }, { 0, 1, 0 }, { -math.sin(y), 0, math.cos(y) } }
	local rz = { { math.cos(z), -math.sin(z), 0 }, { math.sin(z), math.cos(z), 0 }, { 0, 0, 1 } }
	return mul(rz, mul(ry, rx))
end

-- Rounds off the float dust a turn leaves, so saved numbers stay short.
local function tidy(v)
	local r = math.floor(v * 1e6 + 0.5) / 1e6
	return r == 0 and 0 or r
end

local function tidied(v)
	return { tidy(v[1]), tidy(v[2]), tidy(v[3]) }
end

-- The degrees about x, then y, then z that make turn `m`.
local function anglesOf(m)
	local sy = math.max(-1, math.min(1, -m[3][1]))
	local x, z
	if math.abs(sy) > 1 - 1e-9 then
		x, z = 0, math.atan2(-m[1][2], m[2][2])
	else
		x, z = math.atan2(m[3][2], m[3][3]), math.atan2(m[2][1], m[1][1])
	end
	return tidied({ math.deg(x), math.deg(math.asin(sy)), math.deg(z) })
end

local function scaleOf(t)
	local s = t.scale or 1
	return type(s) == "number" and { s, s, s } or s
end

-- Node transform `t` as an affine map: scale, turn, then move.
local function affineOf(t)
	t = t or {}
	return { m = mul(rotationOf(t.rotate or { 0, 0, 0 }), diagonal(scaleOf(t))), t = t.move or { 0, 0, 0 } }
end

-- a after b.
local function compose(a, b)
	local t = apply3(a.m, b.t)
	return { m = mul(a.m, b.m), t = { t[1] + a.t[1], t[2] + a.t[2], t[3] + a.t[3] } }
end

local IDENTITY = { m = diagonal({ 1, 1, 1 }), t = { 0, 0, 0 } }

-- The nodes from the root down to node `id`'s parent, prefab instances'
-- own trees skipped; nil when no node has that id.
local function ancestors(node, id, path)
	if node.id == id then
		return path
	end
	if node.kind == "prefab" then
		return nil
	end
	path[#path + 1] = node
	for _, child in ipairs(node.children or {}) do
		local found = ancestors(child, id, path)
		if found then
			return found
		end
	end
	path[#path] = nil
	return nil
end

-- The selected nodes not under another selected node, each with the map
-- from its parent's space to the design's.
local function targets(scene)
	local selected, out = {}, {}
	for _, id in ipairs(scene.selection) do
		selected[id] = true
	end
	for _, id in ipairs(scene.selection) do
		local path = ancestors(scene.root, id, {})
		local inside = false
		local parent = IDENTITY
		for _, node in ipairs(path or {}) do
			inside = inside or selected[node.id]
			parent = compose(parent, affineOf(node.transform))
		end
		if path and not inside then
			out[#out + 1] = { node = Scene.find(scene, id), parent = parent }
		end
	end
	return out
end

-- The drag's own change in the design's space: linear part and the move
-- after it, about the drag's centre.
local function change(drag, amount)
	if drag.mode == "move" then
		return diagonal({ 1, 1, 1 }), amount
	elseif drag.mode == "rotate" then
		local axis = drag.axis or "z"
		local r = { 0, 0, 0 }
		r[axis == "x" and 1 or axis == "y" and 2 or 3] = amount
		return rotationOf(r), { 0, 0, 0 }
	end
	local f = Transform.AXES[drag.axis]
	return f and diagonal({ f[1] == 1 and amount or 1, f[2] == 1 and amount or 1, f[3] == 1 and amount or 1 })
		or diagonal({ amount, amount, amount }), { 0, 0, 0 }
end

-- Node `node`'s scale after an axis scale by `factor` along design axis
-- `k`: on whichever of its own axes `world` (its frame in the design's
-- space) points most nearly along k.
local function scaledOnAxis(node, world, k, factor)
	local s = scaleOf(node.transform)
	local best, most = 1, -1
	for i = 1, 3 do
		local len = math.sqrt(world[1][i] ^ 2 + world[2][i] ^ 2 + world[3][i] ^ 2)
		local share = len > 0 and math.abs(world[k][i]) / len or 0
		if share > most then
			best, most = i, share
		end
	end
	local out = { s[1], s[2], s[3] }
	out[best] = out[best] * factor
	return tidied(out)
end

-- `node`'s id and those of every node under it, prefab instances' own
-- trees skipped, into `ids`.
local function idsUnder(node, ids)
	ids[node.id] = true
	if node.kind ~= "prefab" then
		for _, child in ipairs(node.children or {}) do
			idsUnder(child, ids)
		end
	end
	return ids
end

-- The middle of the selected nodes' geometry, from `targets`
-- (Pick.targets, in whatever space they are in): the centre of its
-- bounds. Nil when the selection has no geometry.
function Transform.centre(scene, targets)
	local ids = {}
	for _, id in ipairs(scene.selection) do
		local node = Scene.find(scene, id)
		if node then
			idsUnder(node, ids)
		end
	end
	local lists = {}
	for _, target in ipairs(targets) do
		if ids[target.id] then
			lists[#lists + 1] = target.triangles
		end
	end
	local b = Mesh.bounds(Mesh.merge(lists))
	return b and { (b.minX + b.maxX) / 2, (b.minY + b.maxY) / 2, (b.minZ + b.maxZ) / 2 }
end

-- Scene edit (History.apply): `drag` (Transform.start) by `amount`
-- (Transform.amount) on every selected node, in the design's space about
-- the drag's centre. A node under another selected node moves with it
-- rather than twice; anything inside a prefab instance is never selected,
-- so only the instance moves. True when it took; false and why when
-- nothing is selected.
--
-- Under a parent that scales unevenly and turns, a turn or axis scale is
-- the nearest a node transform can hold.
function Transform.apply(scene, drag, amount)
	local nodes = targets(scene)
	if #nodes == 0 then
		return false, "nothing selected"
	end
	local linear, shift = change(drag, amount)
	local c = drag.centre
	for _, n in ipairs(nodes) do
		local node, parent = n.node, n.parent
		node.transform = node.transform or {}
		local t = node.transform
		local back = inverse(parent.m)
		local at = compose(parent, { m = IDENTITY.m, t = t.move or { 0, 0, 0 } }).t
		local moved = apply3(linear, sub(at, c))
		moved = { c[1] + moved[1] + shift[1] - parent.t[1], c[2] + moved[2] + shift[2] - parent.t[2], c[3] + moved[3] + shift[3] - parent.t[3] }
		t.move = tidied(apply3(back, moved))
		if drag.mode == "rotate" then
			local turn = mul(back, mul(linear, parent.m))
			t.rotate = anglesOf(mul(turn, rotationOf(t.rotate or { 0, 0, 0 })))
		elseif drag.mode == "scale" then
			if not drag.axis then
				local s = scaleOf(t)
				t.scale = tidied({ s[1] * amount, s[2] * amount, s[3] * amount })
			else
				local world = mul(parent.m, rotationOf(t.rotate or { 0, 0, 0 }))
				local k = drag.axis == "x" and 1 or drag.axis == "y" and 2 or 3
				t.scale = scaledOnAxis(node, world, k, amount)
			end
		end
	end
	return true
end

return Transform
