-- Pool system for ctx.pools.characters. Calls each record's components
-- explicitly, in a visible order (docs/ARCHITECTURE.md "Systems and frame
-- order").
local Mover = require("src.game.components.mover")

local CharacterSystem = {}

local NO_INTENT = { x = 0, y = 0 }

function CharacterSystem.update(ctx)
	for _, c in ipairs(ctx.pools.characters) do
		Mover.apply(c, ctx.intents[c.player] or NO_INTENT, ctx)
	end
end

return CharacterSystem
