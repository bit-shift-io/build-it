-- What a design version costs to place (docs/CONTEXT.md "Baseplate",
-- "Building"). Pure -- no `love.*`.
--
-- For now only the baseplate costs anything (config.costs.baseplatePerTile
-- per footprint tile). Brick costs extend Cost.of when bricks get them.
local Cost = {}

-- The items placing `version` takes: { [item] = n }.
function Cost.of(version, config)
	local tiles = version.width * version.depth
	local cost = {}
	for item, n in pairs(config.costs.baseplatePerTile) do
		cost[item] = n * tiles
	end
	return cost
end

return Cost
