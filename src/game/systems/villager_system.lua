-- Pool system for ctx.pools.villagers (docs/CONTEXT.md "Villager"). Calls
-- each record's components explicitly, in a visible order
-- (docs/ARCHITECTURE.md "Systems and frame order"). Villagers have no
-- player intents: they walk the path their walker holds.
local Walker = require("src.game.components.walker")
local Animator = require("src.game.components.animator")

local VillagerSystem = {}

function VillagerSystem.update(ctx)
	for _, v in ipairs(ctx.pools.villagers) do
		local fromX, fromY = v.x, v.y
		Walker.step(v, ctx)
		Animator.update(v.animator, v.x - fromX, v.y - fromY, ctx.config.character)
	end
end

return VillagerSystem
