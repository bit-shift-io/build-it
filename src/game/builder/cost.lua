-- What a design version costs to place (docs/CONTEXT.md "Baseplate",
-- "Material", "Function brick"). Pure -- no `love.*`.
--
-- The baseplate costs config.costs.baseplatePerTile per footprint tile.
-- Each brick costs config.costs.perStud[material] per stud of its
-- footprint, plus its shape's own `cost` (config.builder.bricks) when it
-- has one -- function, port and storage bricks do.
local Bricks = require("src.game.builder.bricks")

local Cost = {}

local function add(cost, items, times)
	for item, n in pairs(items or {}) do
		cost[item] = (cost[item] or 0) + n * times
	end
end

-- The items placing `version` (a draft or a saved version) takes:
-- { [item] = n }.
function Cost.of(version, config)
	local cost = {}
	add(cost, config.costs.baseplatePerTile, version.width * version.depth)
	for _, b in ipairs(version.bricks) do
		add(cost, config.costs.perStud[b.material], b.width * b.depth)
		add(cost, Bricks.shape(b.shape, config.builder).cost, 1)
	end
	return cost
end

-- The items of `cost` that `totals` ({ [item] = n }) can't cover:
-- { [item] = true }.
function Cost.short(cost, totals)
	local short = {}
	for item, n in pairs(cost) do
		if (totals[item] or 0) < n then
			short[item] = true
		end
	end
	return short
end

return Cost
