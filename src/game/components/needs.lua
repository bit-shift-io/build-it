-- Needs component (docs/CONTEXT.md "Need", "Health", "Hunger", "Tiredness",
-- "Collapse"): plain data on a character or villager record
-- (`record.needs`), each meter a fraction 0..1. Health 1 is full, 0 is
-- collapse; hunger and tiredness 0 is none, 1 is full. Rates and thresholds
-- live in config.needs; the owning pool system calls Needs.tick. Pure.
--   needs = { health, hunger, tiredness }
local Needs = {}

-- Full health, no hunger, no tiredness.
function Needs.new()
	return { health = 1, hunger = 0, tiredness = 0 }
end

local function clamp(x)
	return math.max(0, math.min(1, x))
end

-- Advances `needs` by `dt` seconds with config.needs `cfg`. Hunger and
-- tiredness rise (the player's tiredness, `isPlayer`, stays 0). At full
-- hunger health drains; below the starving threshold it regenerates. A
-- sleeper (`rest`: tiredness lost per second) loses tiredness instead of
-- gaining it.
function Needs.tick(needs, dt, cfg, isPlayer, rest)
	needs.hunger = clamp(needs.hunger + cfg.hungerRate * dt)
	if rest then
		needs.tiredness = clamp(needs.tiredness - rest * dt)
	elseif not isPlayer then
		needs.tiredness = clamp(needs.tiredness + cfg.tirednessRate * dt)
	end
	if needs.hunger >= 1 then
		needs.health = clamp(needs.health - cfg.drainRate * dt)
	elseif needs.hunger < cfg.starvingAt then
		needs.health = clamp(needs.health + cfg.regenRate * dt)
	end
end

-- Whether the owner is hungry or tired enough to eat or sleep before
-- taking work (ADR 0004).
function Needs.inNeed(needs, cfg)
	return needs.hunger >= cfg.hungryAt or needs.tiredness >= cfg.tiredAt
end

-- Whether hunger is at the hungry threshold: the villager eats before
-- taking work (ADR 0004).
function Needs.hungry(needs, cfg)
	return needs.hunger >= cfg.hungryAt
end

-- Whether health is 0.
function Needs.collapsed(needs)
	return needs.health <= 0
end

return Needs
