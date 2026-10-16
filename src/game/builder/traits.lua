-- A design's traits (docs/CONTEXT.md "Trait"): productivity, capacity,
-- reach and health, each summed from its bricks. Every brick adds its
-- material's traits (config.traits[material]), whatever its shape or role.
-- Pure -- no `love.*`.
local Traits = {}

-- The traits in the order the builder lists them.
Traits.NAMES = { "productivity", "capacity", "reach", "health" }

-- The trait totals of `version` (a draft or a saved version):
-- { productivity, capacity, reach, health }.
function Traits.of(version, config)
	local totals = {}
	for _, name in ipairs(Traits.NAMES) do
		totals[name] = 0
	end
	for _, b in ipairs(version.bricks) do
		local traits = config.traits[b.material] or {}
		for _, name in ipairs(Traits.NAMES) do
			totals[name] = totals[name] + (traits[name] or 0)
		end
	end
	return totals
end

Traits.AURA_NAMES = { "walkSpeed", "harvestRate" }

-- The aura totals of `version` (config.auras per brick material):
-- { walkSpeed, harvestRate }, as fractions.
function Traits.auras(version, config)
	local totals = {}
	for _, name in ipairs(Traits.AURA_NAMES) do
		totals[name] = 0
	end
	for _, b in ipairs(version.bricks) do
		local aura = config.auras[b.material] or {}
		for _, name in ipairs(Traits.AURA_NAMES) do
			totals[name] = totals[name] + (aura[name] or 0)
		end
	end
	return totals
end

return Traits
