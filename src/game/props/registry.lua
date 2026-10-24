-- Every prop kind and how to build its variants. Pure -- no `love.*`.
--
-- A kind: { kind = <name>, version = <generator version>, stages = <count>,
--           generate = function(rng, params) -> block model,
--           turns = <true: each variant is a facing, baked turned> }
-- The baked-sprite cache (src/app/bake/prop_cache.lua) keys each kind's
-- sprites by its version, so bumping one generator rebakes that kind only.
local Rng = require("src.core.rng")
local Tree = require("src.game.props.tree")
local Rock = require("src.game.props.rock")
local Bush = require("src.game.props.bush")
local Deer = require("src.game.props.deer")
local Character = require("src.game.props.character")

local Registry = {}

Registry.KINDS = {
	tree = { kind = "tree", version = Tree.VERSION, stages = Tree.STAGES, generate = Tree.generate },
	rock = { kind = "rock", version = Rock.VERSION, stages = Rock.STAGES, generate = Rock.generate },
	bush = { kind = "bush", version = Bush.VERSION, stages = Bush.STAGES, generate = Bush.generate },
}

-- The character (src/game/props/character.lua): baked and cached like a
-- prop, but never a resource node, so not in KINDS. Its variants are the 8
-- facing directions, one model turned (Registry.turn), and its stages the
-- idle and walk frames. `variants` overrides config.props.variants.
Registry.CHARACTER = {
	kind = "character",
	version = Character.VERSION,
	variants = #Character.DIRECTIONS,
	turns = true,
	stages = Character.FRAMES,
	generate = Character.generate,
}

-- The deer (src/game/props/deer.lua): baked like the character, one variant
-- per facing and one stage per animator frame, but never a resource node.
Registry.DEER = {
	kind = "deer",
	version = Deer.VERSION,
	variants = #Character.DIRECTIONS,
	turns = true,
	stages = Character.FRAMES,
	generate = Deer.generate,
}

-- The villager (docs/CONTEXT.md "Villager"): the character's figure in
-- config.villagers.shirt, baked as a kind of its own. The shirt colour is
-- hashed into its version, so a new colour is a new bake key and rebakes.
function Registry.villager(config)
	local shirt = config.villagers.shirt
	return {
		kind = "villager",
		version = Rng.hash(Character.VERSION, shirt[1], shirt[2], shirt[3]),
		variants = #Character.DIRECTIONS,
		turns = true,
		stages = Character.FRAMES,
		generate = function(_rng, params)
			return Character.model(params.stage, shirt)
		end,
	}
end

-- The seed of one (kind, variant). Each gets its own rng from it, never a
-- shared stream, so adding a kind or variant leaves every other unchanged.
function Registry.seed(def, variant, config)
	return Rng.hash(config.props.seed, def.kind, variant)
end

-- The block model of a kind's variant (1..Registry.variants) at a stage.
function Registry.model(def, variant, stage, config)
	return def.generate(Rng.new(Registry.seed(def, variant, config)), { stage = stage, variant = variant })
end

-- How many variants a kind has: its own count, else config.props.variants.
function Registry.variants(def, config)
	return def.variants or config.props.variants
end

-- Degrees a kind's variant bakes turned, clockwise seen from above: for a
-- kind that `turns`, facing k (Character.DIRECTIONS) is (k - 1) x 45; any
-- other kind is baked as generated, 0.
function Registry.turn(def, variant)
	return def.turns and (variant - 1) * 360 / #Character.DIRECTIONS or 0
end

return Registry
