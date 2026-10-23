-- Triangle lists (src/game/geometry/primitives.lua's vertex format): a node
-- tree (src/game/script/api.lua) turned into one list, node transforms,
-- bounds and the clip at ground level. Pure; plain LuaJIT.
local Primitives = require("src.game.geometry.primitives")
local Extrude = require("src.game.geometry.extrude")
local Lathe = require("src.game.geometry.lathe")
local Sweep = require("src.game.geometry.sweep")
local Path = require("src.game.geometry.path")
local Palette = require("src.game.palette")

local Mesh = {}

-- The colour of a node that doesn't set one.
Mesh.DEFAULT_COLOR = { 0.78, 0.72, 0.62 }

-- The colour of geometry made of each material (config.materials) that no
-- node colour paints. Plank is the default colour.
Mesh.MATERIAL_COLORS = {
	plank = Mesh.DEFAULT_COLOR,
	stone = { 0.62, 0.62, 0.6 },
}

local function rotation(degrees)
	local r = math.rad(degrees)
	return math.cos(r), math.sin(r)
end

-- Point or normal (x, y, z) turned by `rotate` (degrees about x, then y,
-- then z; right-handed).
local function rotated(rotate, x, y, z)
	local c, s = rotation(rotate[1])
	y, z = y * c - z * s, y * s + z * c
	c, s = rotation(rotate[2])
	x, z = x * c + z * s, -x * s + z * c
	c, s = rotation(rotate[3])
	x, y = x * c - y * s, x * s + y * c
	return x, y, z
end

-- Point (x, y, z) with node transform `t` applied, as Mesh.transform does.
function Mesh.transformPoint(t, x, y, z)
	local scale = t.scale or { 1, 1, 1 }
	local move = t.move or { 0, 0, 0 }
	x, y, z = rotated(t.rotate or { 0, 0, 0 }, x * scale[1], y * scale[2], z * scale[3])
	return x + move[1], y + move[2], z + move[3]
end

-- `triangles` with node transform `t` applied ({ move, rotate, scale }, any
-- part optional): scaled, then rotated, then moved. Normals follow (by the
-- inverse scale) and a mirroring scale flips the winding back outward.
function Mesh.transform(triangles, t)
	local scale = t.scale or { 1, 1, 1 }
	local rotate = t.rotate or { 0, 0, 0 }
	local move = t.move or { 0, 0, 0 }
	local out = {}
	if scale[1] * scale[2] * scale[3] == 0 then
		-- Flattened to nothing visible.
		return out
	end
	for i, v in ipairs(triangles) do
		local x, y, z = rotated(rotate, v.x * scale[1], v.y * scale[2], v.z * scale[3])
		local nx, ny, nz = rotated(rotate, v.nx / scale[1], v.ny / scale[2], v.nz / scale[3])
		local len = math.sqrt(nx * nx + ny * ny + nz * nz)
		out[i] = {
			x = x + move[1],
			y = y + move[2],
			z = z + move[3],
			nx = nx / len,
			ny = ny / len,
			nz = nz / len,
			r = v.r,
			g = v.g,
			b = v.b,
			material = v.material,
			texture = v.texture,
			slot = v.slot,
		}
	end
	if scale[1] * scale[2] * scale[3] < 0 then
		for i = 1, #out, 3 do
			out[i + 1], out[i + 2] = out[i + 2], out[i + 1]
		end
	end
	return out
end

local QUARTER_TURNS = { N = 0, E = 1, S = 2, W = 3 }

-- `triangles` on a width x depth footprint (model space, its north-west
-- corner on the origin) turned to `facing` like the baker's block models
-- (Model.rotate): each quarter turn clockwise seen from above, (x, y) going
-- to (depth - y, x), so the north edge becomes the east edge. Returns the
-- turned list and the turned footprint's width, depth.
function Mesh.turn(triangles, width, depth, facing)
	local turns = assert(QUARTER_TURNS[facing], "unknown facing " .. tostring(facing))
	local out = {}
	for i, v in ipairs(triangles) do
		local x, y, nx, ny, d = v.x, v.y, v.nx, v.ny, depth
		for k = 1, turns do
			x, y, nx, ny = d - y, x, -ny, nx
			d = k % 2 == 1 and width or depth
		end
		out[i] = { x = x, y = y, z = v.z, nx = nx, ny = ny, nz = v.nz, r = v.r, g = v.g, b = v.b, material = v.material, texture = v.texture, slot = v.slot }
	end
	if turns % 2 == 1 then
		width, depth = depth, width
	end
	return out, width, depth
end

-- Every list in `lists` joined into one.
function Mesh.merge(lists)
	local out = {}
	for _, list in ipairs(lists) do
		for _, v in ipairs(list) do
			out[#out + 1] = v
		end
	end
	return out
end

-- `part`'s vertices made of `material` (a node's: { name, variant, scale,
-- rotation }): the name as their material, the variant and its scale and
-- rotation as their texture, and the material's colour.
local function made(part, material)
	local texture = { variant = material.variant, scale = material.scale, rotation = material.rotation }
	local color = Mesh.MATERIAL_COLORS[material.name] or Mesh.DEFAULT_COLOR
	for _, v in ipairs(part) do
		v.material, v.texture = material.name, texture
		v.r, v.g, v.b = color[1], color[2], color[3]
	end
end

-- `part`'s vertices painted `color` (a node's: { r, g, b } or a team slot
-- name). A slot is kept on each vertex as `slot`, for the baker to resolve
-- to the owner's palette, and drawn in the default palette until then.
local function painted(part, color)
	local slot = type(color) == "string" and color or nil
	local rgb = slot and Palette.DEFAULT[slot] or color
	for _, v in ipairs(part) do
		v.r, v.g, v.b, v.slot = rgb[1], rgb[2], rgb[3], slot
	end
end

-- The kinds whose parts come from their children, which carry their own
-- materials and colours.
local OWNS_CHILDREN = { group = true, prefab = true }

-- The parts of `node` in its own space, appended to `out`; `inherited` and
-- `inheritedColor` are the material and colour of the nearest node above it
-- that sets each, if any.
local function collect(node, out, inherited, inheritedColor)
	local own = {}
	local material = node.material or inherited
	local color = node.color or inheritedColor
	if node.kind == "extrude" then
		-- The solid of its one shape child, which keeps its own transform.
		local shape = node.children[1]
		own[1] = Mesh.transform(Extrude.mesh(shape, node.height, Mesh.DEFAULT_COLOR), shape.transform)
	elseif node.kind == "lathe" then
		local shape = node.children[1]
		own[1] = Mesh.transform(Lathe.mesh(shape, node.angle, node.segments, Mesh.DEFAULT_COLOR), shape.transform)
	elseif node.kind == "sweep" then
		-- Its shape child's outline along its path child, the path's
		-- transform applied; the shape's own transform and plane play no
		-- part (the profile is laid on the path's frames).
		local shape, path = node.children[1], node.children[2]
		local points = {}
		for i, p in ipairs(Path.points(path) or {}) do
			points[i] = { Mesh.transformPoint(path.transform, p[1], p[2], p[3]) }
		end
		local opts = { twist = node.twist, startScale = node.startScale, endScale = node.endScale }
		own[1] = Sweep.mesh(shape, points, opts, Mesh.DEFAULT_COLOR)
	elseif node.children then
		for _, child in ipairs(node.children) do
			collect(child, own, material, color)
		end
	elseif node.kind == "box" then
		own[1] = Primitives.box(node.size, Mesh.DEFAULT_COLOR)
	elseif node.kind == "sphere" then
		own[1] = Primitives.sphere(node.radius, Mesh.DEFAULT_COLOR, node.segments)
	elseif node.kind == "cylinder" then
		own[1] = Primitives.cylinder(node.radius, node.height, node.segments, Mesh.DEFAULT_COLOR)
	elseif node.kind == "wedge" then
		own[1] = Primitives.wedge(node.size, Mesh.DEFAULT_COLOR)
	elseif node.kind == "cone" then
		own[1] = Primitives.cone(node.radius, node.height, node.segments, Mesh.DEFAULT_COLOR)
	elseif node.kind ~= "role" and node.kind ~= "shape" and node.kind ~= "path" then
		error("unknown node kind " .. tostring(node.kind))
	end
	if not OWNS_CHILDREN[node.kind] then
		-- A leaf: its own geometry is made of its material, painted its
		-- colour (which wins over the material's).
		for _, part in ipairs(own) do
			if material then
				made(part, material)
			end
			if color then
				painted(part, color)
			end
		end
	end
	for _, part in ipairs(own) do
		out[#out + 1] = Mesh.transform(part, node.transform)
	end
	return out
end

-- The tree under `root` as one closed triangle list per primitive, each
-- with every transform above it applied. Roles, shapes and paths have no
-- geometry.
function Mesh.parts(root)
	return collect(root, {})
end

-- The tree under `root` as one triangle list.
function Mesh.ofTree(root)
	return Mesh.merge(Mesh.parts(root))
end

-- The vertex a fraction `t` of the way from vertex a to b: position and
-- normal blended (the normal kept unit length), a's colour and material.
local function between(a, b, t)
	local nx, ny, nz = a.nx + (b.nx - a.nx) * t, a.ny + (b.ny - a.ny) * t, a.nz + (b.nz - a.nz) * t
	local len = math.sqrt(nx * nx + ny * ny + nz * nz)
	if len == 0 then
		nx, ny, nz, len = a.nx, a.ny, a.nz, 1
	end
	return {
		x = a.x + (b.x - a.x) * t,
		y = a.y + (b.y - a.y) * t,
		z = a.z + (b.z - a.z) * t,
		nx = nx / len,
		ny = ny / len,
		nz = nz / len,
		r = a.r,
		g = a.g,
		b = a.b,
		material = a.material,
		texture = a.texture,
		slot = a.slot,
	}
end

-- `triangles` with everything below z = 0 cut away (nothing is built below
-- ground). A cut triangle keeps its winding; the cut is left open, as it
-- lies on the ground.
function Mesh.clip(triangles)
	local out = {}
	for i = 1, #triangles, 3 do
		local corners = { triangles[i], triangles[i + 1], triangles[i + 2] }
		local kept = {}
		for k = 1, 3 do
			local a, b = corners[k], corners[k % 3 + 1]
			if a.z >= 0 then
				kept[#kept + 1] = a
			end
			if (a.z >= 0) ~= (b.z >= 0) then
				local cut = between(a, b, a.z / (a.z - b.z))
				cut.z = 0
				kept[#kept + 1] = cut
			end
		end
		for k = 2, #kept - 1 do
			out[#out + 1] = kept[1]
			out[#out + 1] = kept[k]
			out[#out + 1] = kept[k + 1]
		end
	end
	return out
end

-- The box holding every vertex: { minX, minY, minZ, maxX, maxY, maxZ }, or
-- nil for an empty list.
function Mesh.bounds(triangles)
	if #triangles == 0 then
		return nil
	end
	local inf = math.huge
	local b = { minX = inf, minY = inf, minZ = inf, maxX = -inf, maxY = -inf, maxZ = -inf }
	for _, v in ipairs(triangles) do
		b.minX, b.maxX = math.min(b.minX, v.x), math.max(b.maxX, v.x)
		b.minY, b.maxY = math.min(b.minY, v.y), math.max(b.maxY, v.y)
		b.minZ, b.maxZ = math.min(b.minZ, v.z), math.max(b.maxZ, v.z)
	end
	return b
end

return Mesh
