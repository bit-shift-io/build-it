-- Despawn sweep for ctx.pools.nodes: removes nodes marked dead (a rock with
-- nothing left). The only place nodes leave the pool. ctx.pools.nodes is the
-- world's node pool, so removal goes through World.removeNode to clear the
-- tile too.
local World = require("src.game.world")

local NodeSystem = {}

function NodeSystem.despawn(ctx)
	local dead = {}
	for _, n in ipairs(ctx.pools.nodes) do
		if n.dead then
			table.insert(dead, n)
		end
	end
	for _, n in ipairs(dead) do
		World.removeNode(ctx.world, n)
	end
end

return NodeSystem
