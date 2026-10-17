local Deer = require("src.game.props.deer")
local Character = require("src.game.props.character")
local Registry = require("src.game.props.registry")
local Model = require("src.game.blocks.model")
local Rng = require("src.core.rng")

local function deer(variant, stage)
	return Deer.generate(Rng.new(1), { variant = variant, stage = stage })
end

local function signature(model)
	local parts = {}
	for _, c in ipairs(model.cells) do
		parts[#parts + 1] = c.x .. "," .. c.y .. "," .. c.z
	end
	table.sort(parts)
	return table.concat(parts, ";")
end

test("a deer fits its 1x1 footprint, in every facing and frame", function()
	for variant = 1, #Character.DIRECTIONS do
		for stage = 1, Character.FRAMES do
			local model = deer(variant, stage)
			assertTrue(#model.cells > 20, "expected a body")
			local b = Model.bounds(model)
			assertTrue(b.minX >= 0 and b.minY >= 0 and b.maxX <= 16 and b.maxY <= 16, "inside the tile")
			assertEqual(0, b.minZ)
		end
	end
end)

test("facings and walk frames differ; the same input is identical", function()
	assertEqual(signature(deer(3, 2)), signature(deer(3, 2)))
	assertTrue(signature(deer(1, 1)) ~= signature(deer(3, 1)), "north and east differ")
	assertTrue(signature(deer(3, 1)) ~= signature(deer(3, 2)), "walk differs from standing")
	assertEqual(signature(deer(1, 1)), signature(deer(2, 1)), "a diagonal takes its cardinal base")
end)

test("the deer is registered with a variant per facing and a stage per frame", function()
	assertEqual("deer", Registry.DEER.kind)
	assertEqual(8, Registry.variants(Registry.DEER, { props = { variants = 3 } }))
	assertEqual(Character.FRAMES, Registry.DEER.stages)
end)
