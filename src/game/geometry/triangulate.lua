-- Ear clipping (docs/CONTEXT.md "Shape"): a simple polygon cut into
-- triangles. Pure; plain LuaJIT.
local Triangulate = {}

local function cross(a, b, c)
	return (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1])
end

-- Whether point p lies inside or on the edge of triangle a, b, c (counter-
-- clockwise).
local function inside(a, b, c, p)
	return cross(a, b, p) >= 0 and cross(b, c, p) >= 0 and cross(c, a, p) >= 0
end

-- The triangles of counter-clockwise `outline` ({ { x, y }, ... }) as
-- index triples { i, j, k } into it, each counter-clockwise, together
-- covering it exactly. A corner is clipped when it turns left and no other
-- corner lies in the triangle it cuts off; collinear corners are clipped as
-- flat triangles once no ear is left, so every polygon finishes.
function Triangulate.polygon(outline)
	local ring = {}
	for i = 1, #outline do
		ring[i] = i
	end
	local out = {}
	while #ring > 3 do
		local n, clip = #ring, nil
		for pass = 1, 2 do
			for k = 1, n do
				local ia, ib, ic = ring[(k - 2) % n + 1], ring[k], ring[k % n + 1]
				local a, b, c = outline[ia], outline[ib], outline[ic]
				local turn = cross(a, b, c)
				if (pass == 1 and turn > 0) or (pass == 2 and turn >= 0) then
					local free = true
					for _, other in ipairs(ring) do
						if other ~= ia and other ~= ib and other ~= ic and inside(a, b, c, outline[other]) then
							free = false
							break
						end
					end
					if free then
						clip = k
						break
					end
				end
			end
			if clip then
				break
			end
		end
		assert(clip, "can't triangulate this outline")
		local ia, ib, ic = ring[(clip - 2) % n + 1], ring[clip], ring[clip % n + 1]
		out[#out + 1] = { ia, ib, ic }
		table.remove(ring, clip)
	end
	out[#out + 1] = { ring[1], ring[2], ring[3] }
	return out
end

return Triangulate
