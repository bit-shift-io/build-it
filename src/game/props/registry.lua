-- Every prop kind and how to build its variants. Pure -- no `love.*`.
--
-- A kind: { kind = <name>, version = <generator version>, stages = <count>,
--           generate = function(rng, params) -> block model }
-- The baked-sprite cache (src/app/bake/prop_cache.lua) keys each kind's
-- sprites by its version, so bumping one generator rebakes that kind only.
local Rng = require("src.core.rng")
local Tree = require("src.game.props.tree")
local Rock = require("src.game.props.rock")

local Registry = {}

Registry.KINDS = {
	tree = { kind = "tree", version = Tree.VERSION, stages = Tree.STAGES, generate = Tree.generate },
	rock = { kind = "rock", version = Rock.VERSION, stages = Rock.STAGES, generate = Rock.generate },
}

-- The seed of one (kind, variant). Each gets its own rng from it, never a
-- shared stream, so adding a kind or variant leaves every other unchanged.
function Registry.seed(def, variant, config)
	return Rng.hash(config.props.seed, def.kind, variant)
end

-- The block model of a kind's variant (1..config.props.variants) at a stage.
function Registry.model(def, variant, stage, config)
	return def.generate(Rng.new(Registry.seed(def, variant, config)), { stage = stage })
end

return Registry
