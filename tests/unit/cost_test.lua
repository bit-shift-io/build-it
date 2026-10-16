-- Cost.of (docs/CONTEXT.md "Material", "Baseplate", "Function brick"): the
-- baseplate per tile, each brick per stud by material, plus a function,
-- port or storage brick's own cost.
local Cost = require("src.game.builder.cost")
local Draft = require("src.game.builder.draft")
local Bricks = require("src.game.builder.bricks")
local Config = require("src.game.config")

local CFG = Config.builder
local PER_TILE = Config.costs.baseplatePerTile.plank

local function held(shape, material)
	return { shape = shape, rotation = 0, material = material or "plank", paint = 1 }
end

test("an empty draft costs its baseplate per tile", function()
	local d = Draft.new()
	d.width, d.depth = 3, 2
	local cost = Cost.of(d, Config)
	assertEqual(6 * PER_TILE, cost.plank)
	assertEqual(nil, cost.stone)
end)

test("each brick costs its material per stud of footprint", function()
	local d = Draft.new()
	d.width = 2
	assert(Draft.place(d, 0, 0, 0, CFG, held("2x4", "stone")))
	assert(Draft.place(d, 0, 2, 0, CFG, held("1x2", "plank")))
	local cost = Cost.of(d, Config)
	assertEqual(8 * Config.costs.perStud.stone.stone, cost.stone)
	assertEqual(2 * PER_TILE + 2 * Config.costs.perStud.plank.plank, cost.plank)
end)

test("function, port and storage bricks add their own cost", function()
	for _, name in ipairs({ "saw", "pickaxe", "planter", "sawbench", "input", "output", "storage" }) do
		local d = Draft.new()
		d.width, d.depth = 2, 2
		local plain = Cost.of(d, Config)
		local b = assert(Draft.place(d, 0, 0, 0, CFG, held(name, "stone")))
		local own = assert(Bricks.shape(name, CFG).cost, name .. " has a cost")
		local cost = Cost.of(d, Config)
		local studs = b.width * b.depth
		for _, item in ipairs({ "plank", "stone" }) do
			local material = item == "stone" and studs or 0
			assertEqual((plain[item] or 0) + material + (own[item] or 0), cost[item] or 0, name .. " " .. item)
		end
	end
end)
