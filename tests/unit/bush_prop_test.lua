local Bush = require("src.game.props.bush")
local Registry = require("src.game.props.registry")
local Config = require("src.game.config")
local Rng = require("src.core.rng")

local function signature(model)
	local parts = {}
	for _, c in ipairs(model.cells) do
		parts[#parts + 1] = string.format("%d,%d,%d,%.3f,%.3f,%.3f", c.x, c.y, c.z, c.color[1], c.color[2], c.color[3])
	end
	table.sort(parts)
	return table.concat(parts, ";")
end

local function bush(seed, stage)
	return Bush.generate(Rng.new(seed), { stage = stage or 1 })
end

local function berries(model)
	local n = 0
	for _, c in ipairs(model.cells) do
		if c.color[1] > 0.45 or c.color[3] > 0.6 then -- no leaf is that red or blue
			n = n + 1
		end
	end
	return n
end

test("the same seed gives an identical bush and different seeds differ", function()
	assertEqual(signature(bush(5)), signature(bush(5)))
	assertTrue(signature(bush(5)) ~= signature(bush(6)))
end)

test("a bush has three stages: berries thin out and the last has none", function()
	assertEqual(3, Bush.STAGES)
	for seed = 1, 20 do
		local full, some, empty = berries(bush(seed, 1)), berries(bush(seed, 2)), berries(bush(seed, 3))
		assertTrue(full > some and some > 0 and empty == 0, string.format("seed %d: %d, %d, %d berries", seed, full, some, empty))
		assertTrue(#bush(seed, 3).cells > 0, "an empty bush still has leaves")
	end
end)

test("a bush sits inside its 1x1 footprint on the ground", function()
	for seed = 1, 8 do
		local m = bush(seed)
		assertEqual(16, m.cellsPerTile)
		assertEqual(1, m.width)
		assertEqual(1, m.depth)
		for _, c in ipairs(m.cells) do
			assertTrue(c.x >= 0 and c.x < 16 and c.y >= 0 and c.y < 16 and c.z >= 0, "inside the footprint")
		end
	end
end)

test("the registry has the bush kind with all variants different", function()
	local def = Registry.KINDS.bush
	assertEqual(Bush.STAGES, def.stages)
	local seen = {}
	for v = 1, Config.props.variants do
		local sig = signature(Registry.model(def, v, 1, Config))
		assertFalse(seen[sig], "variant " .. v .. " is new")
		seen[sig] = true
	end
end)
