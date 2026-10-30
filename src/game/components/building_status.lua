-- The building card's text (docs/CONTEXT.md "Building card"): pure functions
-- from a building or a construction site. Drawing is src/app/render/card.lua's
-- job. A line is a string, or { text, swatch = <colour> } to draw a colour
-- swatch before it. Pure -- no `love.*`.
local Aura = require("src.game.components.aura")
local ReachOutline = require("src.game.buildings.reach_outline")

local BuildingStatus = {}

local function sorted(counts)
	local items = {}
	for item, n in pairs(counts) do
		if n > 0 then
			items[#items + 1] = item
		end
	end
	table.sort(items)
	return items
end

local function contents(prefix, store)
	local parts = {}
	for _, item in ipairs(sorted(store.counts)) do
		parts[#parts + 1] = store.counts[item] .. " " .. item
	end
	if #parts > 0 then
		return prefix .. ": " .. table.concat(parts, ", ")
	end
end

local function operatorName(building, ability)
	for _, fb in ipairs(building.functionBricks or {}) do
		if fb.ability == ability then
			if fb.operator then
				local v = fb.operator.villager
				return v and v.name or "Villager"
			end
			return "no operator"
		end
	end
end

-- The card's lines for `record`, a building or a site (site.cost set), in
-- `config`: design name; for a site "Construction site" and delivered/needed
-- per material; a swatch row per reach outline (ability, reach, operator
-- name or "no operator" on a building); productivity, capacity and health;
-- and for a building its storage and port buffers.
function BuildingStatus.lines(record, config)
	local isSite = record.cost ~= nil
	local blueprint = record.blueprint
	local lines = { record.design or "Building" }
	if isSite then
		lines[#lines + 1] = "Construction site"
		for _, item in ipairs(sorted(record.cost)) do
			lines[#lines + 1] = string.format("%s: %d/%d", item, record.delivered.counts[item] or 0, record.cost[item])
		end
	end
	local aura = blueprint.auras
	for _, o in ipairs(ReachOutline.of(blueprint, record.tileX, record.tileY, record.facing, config)) do
		local text
		if o.kind == "aura" then
			text = string.format("Aura, reach %d", o.reach)
		else
			local ability = o.ability:sub(1, 1):upper() .. o.ability:sub(2)
			text = string.format("%s, reach %d", ability, o.reach)
			local who = not isSite and operatorName(record, o.ability)
			if who then
				text = text .. ", " .. who
			end
		end
		lines[#lines + 1] = { text = text, swatch = o.color }
		if o.kind == "aura" then
			for _, line in ipairs(Aura.lines(aura)) do
				lines[#lines + 1] = line
			end
		end
	end
	local traits = record.traits or blueprint.traits
	lines[#lines + 1] = string.format("Productivity %g", traits.productivity)
	lines[#lines + 1] = string.format("Capacity %g", traits.capacity)
	lines[#lines + 1] = string.format("Health %g", traits.health)
	if not isSite then
		local storage = contents("Storage", record.storage)
		if storage then
			lines[#lines + 1] = storage
		end
		for _, port in ipairs(record.ports) do
			local text = contents(port.kind == "input" and "Input" or "Output", port.buffer)
			if text then
				lines[#lines + 1] = text
			end
		end
	end
	return lines
end

return BuildingStatus
