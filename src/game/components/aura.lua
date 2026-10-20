-- Aura component (docs/CONTEXT.md "Aura"): the walk-speed and work-rate
-- bonuses a character or villager gets from buildings whose reach it stands
-- within.
-- Auras of several buildings add up. Called by CharacterSystem. Pure -- no
-- `love.*`.
local FunctionBrick = require("src.game.components.function_brick")

local Aura = {}

Aura.NAMES = { "walkSpeed", "harvestRate" }
Aura.LABELS = { walkSpeed = "Walk speed", harvestRate = "Work rate" }

-- Tiles from tile (x, y) to the nearest footprint tile of `building`.
local function distance(building, x, y)
	local dx = math.max(building.tileX - x, 0, x - (building.tileX + building.width - 1))
	local dy = math.max(building.tileY - y, 0, y - (building.tileY + building.depth - 1))
	return math.max(dx, dy)
end

-- { walkSpeed, harvestRate } fractions summed over the buildings in whose
-- reach character `c` stands.
function Aura.at(ctx, c)
	local total = { walkSpeed = 0, harvestRate = 0 }
	local tile = ctx.config.tileSize
	local x, y = math.floor(c.x / tile), math.floor(c.y / tile)
	for _, b in ipairs(ctx.pools.buildings) do
		if distance(b, x, y) <= FunctionBrick.reach(b.traits, ctx.config) then
			for _, name in ipairs(Aura.NAMES) do
				total[name] = total[name] + b.aura[name]
			end
		end
	end
	return total
end

-- `dt` scaled by the work-rate aura kept on villager `v` (computed each step
-- by VillagerSystem); unscaled when it has none yet.
function Aura.work(v, dt)
	return dt * (1 + (v.aura and v.aura.harvestRate or 0))
end

-- Display lines ("Walk speed +0.5%") for each aura above 0, one decimal.
function Aura.lines(aura)
	local lines = {}
	for _, name in ipairs(Aura.NAMES) do
		if aura[name] > 0 then
			table.insert(lines, string.format("%s +%.1f%%", Aura.LABELS[name], aura[name] * 100))
		end
	end
	return lines
end

return Aura
