local Rock = require("src.game.props.rock")
local Model = require("src.game.blocks.model")
local Rng = require("src.core.rng")

-- A model as one comparable string, cell order ignored.
local function signature(model)
	local parts = {}
	for _, c in ipairs(model.cells) do
		parts[#parts + 1] = string.format("%d,%d,%d,%s,%.3f,%.3f,%.3f", c.x, c.y, c.z, c.shape, c.color[1], c.color[2], c.color[3])
	end
	table.sort(parts)
	return model.cellsPerTile .. ":" .. model.width .. "x" .. model.depth .. "|" .. table.concat(parts, ";")
end

local function rock(seed, stage)
	return Rock.generate(Rng.new(seed), { stage = stage or 1 })
end

test("the same seed gives an identical rock", function()
	assertEqual(signature(rock(77)), signature(rock(77)))
end)

test("different seeds give different rocks", function()
	local seen = {}
	for seed = 1, 8 do
		local sig = signature(rock(Rng.hash("rock", seed)))
		assertFalse(seen[sig], "expected seed " .. seed .. " to give a new rock")
		seen[sig] = true
	end
end)

test("each stage shrinks the rock down to a last chunk", function()
	for seed = 1, 40 do
		local full, half, chunk = #rock(seed, 1).cells, #rock(seed, 2).cells, #rock(seed, 3).cells
		assertTrue(full > half and half > chunk and chunk > 0, string.format("seed %d: %d, %d, %d cells", seed, full, half, chunk))
	end
end)

test("a rock is 16 voxels per tile and sits inside its 1x1 footprint on the ground", function()
	for seed = 1, 8 do
		for stage = 1, Rock.STAGES do
			local m = rock(seed, stage)
			local b = Model.bounds(m)
			assertEqual(16, m.cellsPerTile)
			assertEqual(1, m.width)
			assertEqual(1, m.depth)
			assertTrue(b.minX >= 0 and b.minY >= 0 and b.maxX <= 16 and b.maxY <= 16, "inside the footprint")
			assertEqual(0, b.minZ, "sitting on the ground")
		end
	end
end)

test("the registry's rock variants are all different", function()
	local Registry = require("src.game.props.registry")
	local Config = require("src.game.config")
	local seen = {}
	for variant = 1, Config.props.variants do
		local sig = signature(Registry.model(Registry.KINDS.rock, variant, 1, Config))
		assertFalse(seen[sig], "expected variant " .. variant .. " to be new")
		seen[sig] = true
	end
end)
