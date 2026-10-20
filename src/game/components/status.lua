-- The hover card's text (docs/CONTEXT.md "Name", "Job", "Experience",
-- "Load"): pure functions from a character or villager record. Drawing the
-- card is src/app/render/card.lua's job. Pure -- no `love.*`.
local Needs = require("src.game.components.needs")
local Aura = require("src.game.components.aura")

local Status = {}

local function capitalise(s)
	return s:sub(1, 1):upper() .. s:sub(2)
end

-- What the record is doing: "Collapsed" at 0 health, else read from its job:
-- "Operating Saw", "Hauling plank", "Building", "Eating", "Feeding Ada", "Sleeping", "Sleeping rough", else "Idle".
function Status.activity(r)
	if Needs.collapsed(r.needs) then
		return "Collapsed"
	end
	local job = r.job
	if job then
		if job.kind == "operate" then
			return "Operating " .. capitalise(job.brick.ability)
		elseif job.kind == "haul" then
			return "Hauling " .. job.item
		elseif job.kind == "build" then
			return "Building"
		elseif job.kind == "eat" then
			return "Eating"
		elseif job.kind == "sleep" then
			return job.brick and "Sleeping" or "Sleeping rough"
		elseif job.kind == "feed" then
			return "Feeding " .. (job.target.name or "Villager")
		end
	end
	return "Idle"
end

-- The HUD's hunger warning: "Starving" from the starving threshold,
-- "Hungry" from the hungry one, nil below it. `cfg` is config.needs.
function Status.hunger(needs, cfg)
	if needs.hunger >= cfg.starvingAt then
		return "Starving"
	elseif needs.hunger >= cfg.hungryAt then
		return "Hungry"
	end
end

-- The card's need bars, { label, value } with value 0..1: health, hunger
-- and, for a villager, tiredness (the player's stays at 0).
function Status.bars(r)
	local bars = {
		{ label = "Health", value = r.needs.health },
		{ label = "Hunger", value = r.needs.hunger },
	}
	if r.load then
		bars[#bars + 1] = { label = "Tiredness", value = r.needs.tiredness }
	end
	return bars
end

-- The card's lines: name, activity, and for a villager its load and its
-- experience per role (sorted by role). The player has neither. `aura`
-- (optional, { walkSpeed, harvestRate }) adds its non-zero lines last.
function Status.lines(r, aura)
	local lines = { r.name or "Villager", Status.activity(r) }
	if r.load then
		Status.loadAndExperience(r, lines)
	end
	if aura then
		for _, line in ipairs(Aura.lines(aura)) do
			lines[#lines + 1] = line
		end
	end
	return lines
end

function Status.loadAndExperience(r, lines)
	lines[#lines + 1] = r.load.count > 0 and ("Load: " .. r.load.count .. " " .. r.load.item) or "Load: empty"
	local roles = {}
	for role in pairs(r.xp) do
		roles[#roles + 1] = role
	end
	table.sort(roles)
	if #roles == 0 then
		lines[#lines + 1] = "No experience"
	end
	for _, role in ipairs(roles) do
		lines[#lines + 1] = role .. ": " .. r.xp[role]
	end
end

return Status
