-- Reach outlines of a blueprint at a tile and facing.
local ReachOutline = require("src.game.buildings.reach_outline")
local FunctionBrick = require("src.game.components.function_brick")
local Config = require("src.game.config")
local Designs = require("tests.support.designs")

local function outlines(text, facing)
	return ReachOutline.of(Designs.blueprint(text), 10, 20, facing or "N", Config)
end

local function operators(list)
	local out = {}
	for _, o in ipairs(list) do
		if o.kind == "operator" then
			table.insert(out, o)
		end
	end
	return out
end

test("each operator brick gets an outline of its reach around the footprint", function()
	local text = Designs.floor(3, 2, Designs.ability("saw", 0.5, 0.5), Designs.ability("pickaxe", 1.5, 0.5))
	local list = operators(outlines(text))
	local traits = Designs.blueprint(text).traits
	local reach = FunctionBrick.reach(traits, Config, "saw")
	assertEqual(2, #list)
	assertEqual("operator", list[1].kind)
	assertEqual("saw", list[1].ability)
	assertEqual(reach, list[1].reach)
	assertEqual(10 - reach, list[1].x)
	assertEqual(20 - reach, list[1].y)
	assertEqual(3 + 2 * reach, list[1].width)
	assertEqual(2 + 2 * reach, list[1].depth)
	assertEqual(Config.reachColors.abilities.saw, list[1].color)
	assertEqual("pickaxe", list[2].ability)
	assertEqual(FunctionBrick.reach(traits, Config, "pickaxe"), list[2].reach)
end)

test("depot, bed and canteen bricks give no outline", function()
	local text = Designs.floor(3, 2, Designs.ability("depot", 0.5, 0.5), Designs.ability("bed", 1.5, 0.5), Designs.ability("canteen", 2.5, 0.5))
	assertEqual(0, #operators(outlines(text)))
end)

test("the aura outline uses the base reach and is absent at zero auras", function()
	local bp = Designs.blueprint(Designs.floor(2, 2))
	local list = outlines(Designs.floor(2, 2))
	local hasAura = false
	for _, v in pairs(bp.auras) do
		hasAura = hasAura or v > 0
	end
	assertEqual(hasAura and 1 or 0, #list)
	if hasAura then
		assertEqual("aura", list[1].kind)
		assertEqual(FunctionBrick.reach(bp.traits, Config), list[1].reach)
	end
	local zero = {}
	for k in pairs(bp.auras) do
		zero[k] = 0
	end
	local copy = setmetatable({ auras = zero }, { __index = bp })
	assertEqual(0, #ReachOutline.of(copy, 0, 0, "N", Config))
end)

test("an aura above zero adds an aura outline after the operators", function()
	local bp = Designs.blueprint(Designs.floor(2, 2, Designs.ability("saw", 0.5, 0.5)))
	local auras = {}
	for k in pairs(bp.auras) do
		auras[k] = 0.01
	end
	local copy = setmetatable({ auras = auras }, { __index = bp })
	local list = ReachOutline.of(copy, 0, 0, "N", Config)
	assertEqual(2, #list)
	assertEqual("aura", list[2].kind)
	assertEqual(Config.reachColors.aura, list[2].color)
end)

test("facing E swaps width and depth", function()
	local text = Designs.floor(3, 2, Designs.ability("saw", 0.5, 0.5))
	local n = outlines(text, "N")[1]
	local e = outlines(text, "E")[1]
	assertEqual(n.width, e.depth)
	assertEqual(n.depth, e.width)
end)
