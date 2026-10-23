-- A design's footprint (docs/CONTEXT.md "Footprint"): the ground its
-- geometry covers, rounded up to whole tiles. Computed from the model's
-- bounds (src/game/geometry/mesh.lua), never set by hand. Pure; plain LuaJIT.
local Footprint = {}

-- Bounds this close over a whole tile count are rounding error, not a part
-- that reaches into the next tile.
local EPSILON = 1e-6

local function tiles(length)
	return math.max(1, math.ceil(length - EPSILON))
end

-- The footprint of `bounds` (Mesh.bounds of clipped geometry): its corner
-- { x, y } at the bounds' north-west, and its size { width, depth } in whole
-- tiles, at least 1. nil when there are no bounds.
function Footprint.of(bounds)
	if not bounds then
		return nil
	end
	return {
		x = bounds.minX,
		y = bounds.minY,
		width = tiles(bounds.maxX - bounds.minX),
		depth = tiles(bounds.maxY - bounds.minY),
	}
end

return Footprint
