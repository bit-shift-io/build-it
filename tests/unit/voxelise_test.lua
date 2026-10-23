-- Voxelising (src/game/geometry/voxelise.lua): closed parts counted in
-- voxels, 16 per tile side, by sampling voxel centres. Parts come from
-- design scripts through the sandbox, as the compiler gets them.
local Sandbox = require("src.game.script.sandbox")
local Mesh = require("src.game.geometry.mesh")
local Voxelise = require("src.game.geometry.voxelise")

local PER_TILE = 16
local PER_CUBIC_TILE = PER_TILE * PER_TILE * PER_TILE

local function parts(text, material)
	local out = {}
	for i, triangles in ipairs(Mesh.parts(assert(Sandbox.run(text, "design")).root)) do
		out[i] = { triangles = Mesh.clip(triangles), material = material or "plank" }
	end
	return out
end

test("a unit box holds 16 x 16 x 16 voxels", function()
	assertEqual(PER_CUBIC_TILE, Voxelise.of(parts("return box{}"), PER_TILE).plank)
end)

test("a box half below ground counts only its part above", function()
	local counts = Voxelise.of(parts("return box{ transform = { move = { 0, 0, -0.5 } } }"), PER_TILE)
	assertEqual(PER_CUBIC_TILE / 2, counts.plank)
end)

test("a sphere's voxels are within 10% of its volume", function()
	-- Radius 1, centred a tile up so none of it is clipped.
	local counts = Voxelise.of(parts("return sphere{ radius = 1, transform = { move = { 0, 0, 1 } } }"), PER_TILE)
	local volume = 4 / 3 * math.pi * PER_CUBIC_TILE
	assertNear(volume, counts.plank, volume * 0.1)
end)

test("overlapping boxes count their shared voxels once", function()
	local counts = Voxelise.of(parts("return group{ box{}, box{ transform = { move = { 0.5, 0, 0 } } } }"), PER_TILE)
	assertEqual(PER_CUBIC_TILE * 3 / 2, counts.plank)
end)

test("where parts of two materials overlap, the earlier part's material wins", function()
	local out = parts("return box{}", "plank")
	for _, part in ipairs(parts("return box{ transform = { move = { 0.5, 0, 0 } } }", "stone")) do
		out[#out + 1] = part
	end
	local counts = Voxelise.of(out, PER_TILE)
	assertEqual(PER_CUBIC_TILE, counts.plank)
	assertEqual(PER_CUBIC_TILE / 2, counts.stone)
end)

test("cylinders, cones and wedges are closed: their voxels are within 10% of their volumes", function()
	local cases = {
		{ "return cylinder{ radius = 1, height = 2 }", math.pi * 2 },
		{ "return cone{ radius = 1, height = 3 }", math.pi * 3 / 3 },
		{ "return wedge{ size = { 2, 1, 3 } }", 2 * 1 * 3 / 2 },
	}
	for _, case in ipairs(cases) do
		local volume = case[2] * PER_CUBIC_TILE
		local counts = Voxelise.of(parts(case[1]), PER_TILE)
		assertNear(volume, counts.plank or 0, volume * 0.1, case[1] .. " gave " .. tostring(counts.plank))
	end
end)
