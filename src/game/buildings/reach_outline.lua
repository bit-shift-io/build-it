-- Reach outlines (docs/CONTEXT.md "Reach outline"): for a blueprint placed at
-- a tile and facing, the rectangle each operator function brick reaches and
-- the aura's, the footprint grown by the reach in tiles (reach is Chebyshev
-- distance, FunctionBrick.reach). Pure -- no `love.*`.
local Placement = require("src.game.buildings.placement")
local FunctionBrick = require("src.game.components.function_brick")

local ReachOutline = {}

-- Abilities that need no operator, so reach nothing.
local NO_REACH = { [FunctionBrick.DEPOT] = true, [FunctionBrick.BED] = true, [FunctionBrick.CANTEEN] = true }

local function rect(kind, ability, label, reach, color, tileX, tileY, width, depth)
	return {
		kind = kind,
		ability = ability,
		label = label,
		reach = reach,
		x = tileX - reach,
		y = tileY - reach,
		width = width + 2 * reach,
		depth = depth + 2 * reach,
		color = color,
	}
end

-- { { kind = "operator"|"aura", ability?, label, reach, x, y, width, depth,
-- color }, ... }: one per operator ability brick in role order, then the
-- aura's when any of its auras is above 0. x, y, width, depth are tiles.
function ReachOutline.of(blueprint, tileX, tileY, facing, config)
	local width, depth = Placement.footprint(blueprint, facing)
	local colors = config.reachColors
	local list = {}
	for _, role in ipairs(blueprint.roles.abilities) do
		local ability = role.ability
		if ability and not NO_REACH[ability] then
			local reach = FunctionBrick.reach(blueprint.traits, config, ability)
			local color = colors.abilities[ability] or colors.default
			table.insert(list, rect("operator", ability, ability, reach, color, tileX, tileY, width, depth))
		end
	end
	local aura = false
	for _, v in pairs(blueprint.auras) do
		if v > 0 then
			aura = true
		end
	end
	if aura then
		local reach = FunctionBrick.reach(blueprint.traits, config)
		table.insert(list, rect("aura", nil, "aura", reach, colors.aura, tileX, tileY, width, depth))
	end
	return list
end

return ReachOutline
