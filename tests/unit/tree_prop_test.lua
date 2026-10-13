local Tree = require("src.game.props.tree")
local Rng = require("src.core.rng")

-- A model as one comparable string: every cell's position, shape and colour,
-- sorted so cell order doesn't matter.
local function signature(model)
	local parts = {}
	for _, c in ipairs(model.cells) do
		parts[#parts + 1] = string.format("%d,%d,%d,%s,%.3f,%.3f,%.3f", c.x, c.y, c.z, c.shape, c.color[1], c.color[2], c.color[3])
	end
	table.sort(parts)
	return model.cellsPerTile .. ":" .. model.width .. "x" .. model.depth .. "|" .. table.concat(parts, ";")
end

local function tree(seed, stage)
	return Tree.generate(Rng.new(seed), { stage = stage or 1 })
end

test("the same seed gives an identical tree", function()
	assertEqual(signature(tree(123)), signature(tree(123)))
end)

test("different seeds give different trees", function()
	local seen = {}
	for seed = 1, 8 do
		local sig = signature(tree(Rng.hash("tree", seed)))
		assertFalse(seen[sig], "expected seed " .. seed .. " to give a new tree")
		seen[sig] = true
	end
end)

test("each stage shrinks the tree: full, half-felled, stump", function()
	for seed = 1, 8 do
		local full, half, stump = #tree(seed, 1).cells, #tree(seed, 2).cells, #tree(seed, 3).cells
		assertTrue(full > half and half > stump and stump > 0, string.format("seed %d: %d, %d, %d cells", seed, full, half, stump))
	end
end)

test("a tree is 16 voxels per tile and stands inside its 1x1 footprint on the ground", function()
	local Model = require("src.game.blocks.model")
	for seed = 1, 8 do
		for stage = 1, Tree.STAGES do
			local m = tree(seed, stage)
			local b = Model.bounds(m)
			assertEqual(16, m.cellsPerTile)
			assertEqual(1, m.width)
			assertEqual(1, m.depth)
			assertTrue(b.minX >= 0 and b.minY >= 0 and b.maxX <= 16 and b.maxY <= 16, "inside the footprint")
			assertEqual(0, b.minZ, "standing on the ground")
		end
	end
end)

test("the registry's tree variants are all different", function()
	local Registry = require("src.game.props.registry")
	local Config = require("src.game.config")
	local seen = {}
	for variant = 1, Config.props.variants do
		local sig = signature(Registry.model(Registry.KINDS.tree, variant, 1, Config))
		assertFalse(seen[sig], "expected variant " .. variant .. " to be new")
		seen[sig] = true
	end
end)

test("a tree variant depends only on its kind and variant, not on what was generated before", function()
	local Registry = require("src.game.props.registry")
	local Config = require("src.game.config")
	local before = signature(Registry.model(Registry.KINDS.tree, 3, 1, Config))
	-- Generate other kinds and variants in between; a shared stream would shift.
	local extraKind = { kind = "bush", version = 1, generate = Tree.generate }
	Registry.model(extraKind, 1, 1, Config)
	Registry.model(Registry.KINDS.rock, 3, 1, Config)
	Registry.model(Registry.KINDS.tree, 2, 2, Config)
	assertEqual(before, signature(Registry.model(Registry.KINDS.tree, 3, 1, Config)))
end)

test("a tree variant's stages are cut from the same tree", function()
	local Registry = require("src.game.props.registry")
	local Config = require("src.game.config")
	local full = signature(Registry.model(Registry.KINDS.tree, 5, 1, Config))
	local stump = Registry.model(Registry.KINDS.tree, 5, 3, Config)
	for _, c in ipairs(stump.cells) do
		if c.z == 0 then
			assertTrue(full:find(string.format("%d,%d,0,box,", c.x, c.y), 1, true) ~= nil, "stump base under the tree's trunk")
		end
	end
end)
