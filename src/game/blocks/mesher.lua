-- Turns a block model into a flat triangle list for the baker. Pure -- no
-- `love.*`; plain LuaJIT.
--
-- Output: { <vertex>, ... }, every 3 vertices one triangle, wound so that
-- cross(b - a, c - a) points along the face's outward normal.
--   vertex = { x, y, z, nx, ny, nz, r, g, b }
-- Positions are in model cells (x east, y south, z up; src/game/blocks/model.lua).
local Mesher = {}

-- A face: the side it lies on (nil when it lies on no cell side), its
-- outline as seen by a neighbour on that side, its unit outward normal and
-- its corners in outward winding order, as unit-cell offsets.
local BOX_FACES = {
	{ side = "U", outline = "full", normal = { 0, 0, 1 }, corners = { { 0, 0, 1 }, { 1, 0, 1 }, { 1, 1, 1 }, { 0, 1, 1 } } },
	{ side = "D", outline = "full", normal = { 0, 0, -1 }, corners = { { 0, 0, 0 }, { 0, 1, 0 }, { 1, 1, 0 }, { 1, 0, 0 } } },
	{ side = "E", outline = "full", normal = { 1, 0, 0 }, corners = { { 1, 0, 0 }, { 1, 1, 0 }, { 1, 1, 1 }, { 1, 0, 1 } } },
	{ side = "W", outline = "full", normal = { -1, 0, 0 }, corners = { { 0, 0, 0 }, { 0, 0, 1 }, { 0, 1, 1 }, { 0, 1, 0 } } },
	{ side = "S", outline = "full", normal = { 0, 1, 0 }, corners = { { 0, 1, 0 }, { 0, 1, 1 }, { 1, 1, 1 }, { 1, 1, 0 } } },
	{ side = "N", outline = "full", normal = { 0, -1, 0 }, corners = { { 0, 0, 0 }, { 1, 0, 0 }, { 1, 0, 1 }, { 0, 0, 1 } } },
}

local HALF = math.sqrt(0.5)

-- A slope looking south: full bottom and north back, triangular west and
-- east ends, and the sloped face from the top north edge down to the
-- bottom south edge. Its ends only match the ends of a slope with the same dir.
local SOUTH_SLOPE_FACES = {
	{ side = "D", outline = "full", normal = { 0, 0, -1 }, corners = { { 0, 0, 0 }, { 0, 1, 0 }, { 1, 1, 0 }, { 1, 0, 0 } } },
	{ side = "N", outline = "full", normal = { 0, -1, 0 }, corners = { { 0, 0, 0 }, { 1, 0, 0 }, { 1, 0, 1 }, { 0, 0, 1 } } },
	{ side = "W", outline = "end", normal = { -1, 0, 0 }, corners = { { 0, 0, 0 }, { 0, 0, 1 }, { 0, 1, 0 } } },
	{ side = "E", outline = "end", normal = { 1, 0, 0 }, corners = { { 1, 0, 0 }, { 1, 1, 0 }, { 1, 0, 1 } } },
	{ normal = { 0, HALF, HALF }, corners = { { 0, 0, 1 }, { 1, 0, 1 }, { 1, 1, 0 }, { 0, 1, 0 } } },
}

local CLOCKWISE_SIDE = { N = "E", E = "S", S = "W", W = "N", U = "U", D = "D" }

-- A quarter clockwise turn about the unit cell's vertical centre line.
local function turnFace(face)
	local corners = {}
	for i, p in ipairs(face.corners) do
		corners[i] = { 1 - p[2], p[1], p[3] }
	end
	local n = face.normal
	return {
		side = face.side and CLOCKWISE_SIDE[face.side],
		outline = face.outline,
		normal = { -n[2], n[1], n[3] },
		corners = corners,
	}
end

-- Slope faces per dir, turned from the south-looking slope (S -> W -> N -> E).
local SLOPE_FACES = {}
do
	local faces = SOUTH_SLOPE_FACES
	for _, dir in ipairs({ "S", "W", "N", "E" }) do
		SLOPE_FACES[dir] = {}
		for i, face in ipairs(faces) do
			local f = { side = face.side, normal = face.normal, corners = face.corners, outline = face.outline }
			if f.outline == "end" then
				f.outline = "end:" .. dir
			end
			SLOPE_FACES[dir][i] = f
		end
		local turned = {}
		for i, face in ipairs(faces) do
			turned[i] = turnFace(face)
		end
		faces = turned
	end
end

local function emit(out, cell, face)
	local corners, n, color = face.corners, face.normal, cell.color
	-- A quad fans into (1, 2, 3) and (1, 3, 4); a triangle is just (1, 2, 3).
	for i = 2, #corners - 1 do
		for _, k in ipairs({ 1, i, i + 1 }) do
			local p = corners[k]
			table.insert(out, {
				x = cell.x + p[1],
				y = cell.y + p[2],
				z = cell.z + p[3],
				nx = n[1],
				ny = n[2],
				nz = n[3],
				r = color[1],
				g = color[2],
				b = color[3],
			})
		end
	end
end

local OFFSET = {
	E = { 1, 0, 0 },
	W = { -1, 0, 0 },
	S = { 0, 1, 0 },
	N = { 0, -1, 0 },
	U = { 0, 0, 1 },
	D = { 0, 0, -1 },
}
local OPPOSITE = { E = "W", W = "E", S = "N", N = "S", U = "D", D = "U" }

local function key(x, y, z)
	return x .. "," .. y .. "," .. z
end

local function facesOf(cell)
	if cell.shape == "slope" then
		return assert(SLOPE_FACES[cell.dir], "slope needs a dir N, E, S or W")
	end
	return BOX_FACES
end

-- The outline a cell shows on `side`, or nil when it has no face there.
local function outlineOn(cell, side)
	for _, face in ipairs(facesOf(cell)) do
		if face.side == side then
			return face.outline
		end
	end
	return nil
end

-- A face is hidden when the neighbour on its side shows a full face back,
-- or the exact same outline (two matching slope ends).
local function hidden(face, cell, byPosition)
	if not face.side then
		return false
	end
	local o = OFFSET[face.side]
	local neighbour = byPosition[key(cell.x + o[1], cell.y + o[2], cell.z + o[3])]
	if not neighbour then
		return false
	end
	local back = outlineOn(neighbour, OPPOSITE[face.side])
	return back == "full" or back == face.outline
end

function Mesher.mesh(model)
	local byPosition = {}
	for _, cell in ipairs(model.cells) do
		byPosition[key(cell.x, cell.y, cell.z)] = cell
	end

	local out = {}
	for _, cell in ipairs(model.cells) do
		for _, face in ipairs(facesOf(cell)) do
			if not hidden(face, cell, byPosition) then
				emit(out, cell, face)
			end
		end
	end
	return out
end

return Mesher
