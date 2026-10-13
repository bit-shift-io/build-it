-- Pool system for ctx.pools.buildings: places the buildings players ask
-- for (intent.place, src/game/buildings/placement.lua).
local Placement = require("src.game.buildings.placement")

local BuildingSystem = {}

function BuildingSystem.update(ctx)
	for _, c in ipairs(ctx.pools.characters) do
		local intent = ctx.intents[c.player]
		if intent and intent.place then
			Placement.place(ctx, c, intent.place)
		end
	end
end

return BuildingSystem
