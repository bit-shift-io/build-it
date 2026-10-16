-- The rules a design must keep to be saved (docs/CONTEXT.md "Function
-- brick", "Port"). Pure -- no `love.*`. Every rule reads the bricks' role
-- fields (ability, port), never the design's name.
local Bricks = require("src.game.builder.bricks")

local Validate = {}

local function any(draft, test)
	for _, b in ipairs(draft.bricks) do
		if test(b) then
			return true
		end
	end
	return false
end

-- The rules in the order they are listed: { reason, broken(draft, cfg) }.
local RULES = {
	{
		"no function brick",
		function(d)
			return not any(d, function(b)
				return b.ability ~= nil
			end)
		end,
	},
	{
		"no output port",
		function(d)
			return not any(d, function(b)
				return b.port == "output"
			end)
		end,
	},
	{
		-- A port works only on the footprint edge at ground level.
		"port off edge",
		function(d, cfg)
			return any(d, function(b)
				return b.port ~= nil and Bricks.edge(b, d, cfg) == nil
			end)
		end,
	},
	{
		"saw bench without input",
		function(d)
			local function isSawBench(b)
				return b.ability == "sawbench"
			end
			local function isInput(b)
				return b.port == "input"
			end
			return any(d, isSawBench) and not any(d, isInput)
		end,
	},
}

-- The rules `draft` (a draft or saved version) breaks, as reasons in rule
-- order: "no function brick", "no output port", "port off edge" (a port
-- not on the footprint edge at ground level), "saw bench without input".
-- Empty when the draft is valid. cfg is config.builder.
function Validate.problems(draft, cfg)
	local problems = {}
	for _, rule in ipairs(RULES) do
		if rule[2](draft, cfg) then
			table.insert(problems, rule[1])
		end
	end
	return problems
end

return Validate
