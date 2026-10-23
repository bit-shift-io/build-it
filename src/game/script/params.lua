-- Params (docs/CONTEXT.md "Param"): the values a design script declares
-- with UI.number, UI.bool, UI.choice and UI.color. Pure; plain LuaJIT.
--
-- A param is named after the variable a top-level
--   local radius = UI.number({ default = 3, step = 0.2 })
-- assigns it to; its label defaults to that name. Changing a param in the
-- builder rewrites its default in the script's text: the one edit made to
-- a locked script (docs/CONTEXT.md "Locked script"), touching nothing else.
--
--   param = { kind, label?, default, value, min?, max?, step? (number),
--             options (choice) }; collected params add name and label.
local Lex = require("src.game.script.lex")

local Params = {}

Params.KINDS = { number = true, bool = true, choice = true, color = true }

-- Keywords opening a block that `end` or `until` closes.
local OPENS = { ["function"] = true, ["if"] = true, ["do"] = true, ["repeat"] = true }
local CLOSES = { ["end"] = true, ["until"] = true }
local BRACKETS = { ["("] = 1, ["{"] = 1, ["["] = 1, [")"] = -1, ["}"] = -1, ["]"] = -1 }

local function clamp01(x)
	return math.max(0, math.min(1, x))
end

-- `value` as param `param` may hold it: a number clamped to min and max, a
-- colour's channels clamped to 0..1. Nil and why when it can't be one.
function Params.clamp(param, value)
	local kind = param.kind
	if kind == "number" then
		if type(value) ~= "number" or value ~= value then
			return nil, "must be a number"
		end
		if param.min then
			value = math.max(param.min, value)
		end
		if param.max then
			value = math.min(param.max, value)
		end
		return value
	elseif kind == "bool" then
		if type(value) ~= "boolean" then
			return nil, "must be true or false"
		end
		return value
	elseif kind == "choice" then
		for _, option in ipairs(param.options) do
			if option == value then
				return value
			end
		end
		return nil, "must be one of the options"
	end
	if type(value) ~= "table" then
		return nil, "must be a table of 3 numbers"
	end
	local out = {}
	for i = 1, 3 do
		if type(value[i]) ~= "number" or value[i] ~= value[i] then
			return nil, "must be a table of 3 numbers"
		end
		out[i] = clamp01(value[i])
	end
	return out
end

-- Number param `param`'s value moved `direction` (1 or -1) steps (its step,
-- else 1), clamped, rounded to 12 significant digits so 3 + 0.2 is 3.2.
function Params.step(param, direction)
	local value = param.value + direction * (param.step or 1)
	return (Params.clamp(param, tonumber(string.format("%.12g", value))))
end

-- The top-level `local <name> = UI.<kind>(` or `UI.<kind>{` declarations in
-- `tokens`, in order: { { name, kind, open (the index of the argument
-- table's "{" token) }, ... }.
local function declarations(tokens)
	local out, block, bracket = {}, 0, 0
	for i, t in ipairs(tokens) do
		local word = t.kind == "name" and t.text
		if word and OPENS[word] then
			block = block + 1
		elseif word and CLOSES[word] then
			block = block - 1
		elseif t.kind == "symbol" and BRACKETS[t.text] then
			bracket = bracket + BRACKETS[t.text]
		end
		if word == "local" and block == 0 and bracket == 0 then
			local name, eq, ui, dot, kind = tokens[i + 1], tokens[i + 2], tokens[i + 3], tokens[i + 4], tokens[i + 5]
			local open = i + 6
			if tokens[open] and tokens[open].text == "(" then
				open = open + 1
			end
			if name and name.kind == "name" and eq and eq.text == "=" and ui and ui.text == "UI"
				and dot and dot.text == "." and kind and Params.KINDS[kind.text]
				and tokens[open] and tokens[open].text == "{" then
				out[#out + 1] = { name = name.text, kind = kind.text, open = open }
			end
		end
	end
	return out
end

-- The params a run of `text` declared (Sandbox.run's params), named after
-- their top-level declarations in order; a param declared any other way
-- has no name and is labelled by its kind.
function Params.collect(text, declared)
	local found = declarations(Lex.tokens(text))
	local out, next = {}, 1
	for i, param in ipairs(declared) do
		local copy = {}
		for k, v in pairs(param) do
			copy[k] = v
		end
		local d = found[next]
		if d and d.kind == param.kind then
			copy.name = d.name
			next = next + 1
		end
		copy.label = param.label or copy.name or param.kind
		out[i] = copy
	end
	return out
end

-- `x` in the fewest digits that read back as exactly `x`.
local function number(x)
	for digits = 14, 17 do
		local s = string.format("%." .. digits .. "g", x)
		if tonumber(s) == x then
			return s
		end
	end
	return string.format("%.17g", x)
end

-- `value` as Lua source.
local function literal(value)
	if type(value) == "number" then
		return number(value)
	elseif type(value) == "string" then
		return string.format("%q", value)
	elseif type(value) == "table" then
		local parts = {}
		for i, v in ipairs(value) do
			parts[i] = literal(v)
		end
		return "{ " .. table.concat(parts, ", ") .. " }"
	end
	return tostring(value)
end

-- `text` with the default of the param declared at top level as
-- `local <name> = UI.<kind>(...)` set to `value`; only that default's
-- characters change (or `default = value, ` is added when it has none).
-- Nil and why when no such declaration exists.
function Params.rewrite(text, name, value)
	local tokens = Lex.tokens(text)
	for _, d in ipairs(declarations(tokens)) do
		if d.name == name then
			-- first: the index of the default's first token; last: its last.
			local depth, first, last = 0, nil, nil
			for i = d.open, #tokens do
				local t = tokens[i]
				if t.kind == "symbol" and BRACKETS[t.text] then
					depth = depth + BRACKETS[t.text]
				end
				local ends = (depth == 1 and (t.text == "," or t.text == ";")) or depth == 0
				if first and i >= first then
					if ends then
						break
					end
					last = i
				elseif not first and depth == 1 and t.text == "default" and (tokens[i + 1] or {}).text == "=" then
					first = i + 2
				end
				if depth == 0 then
					break
				end
			end
			if first and last then
				return text:sub(1, tokens[first].first - 1) .. literal(value) .. text:sub(tokens[last].last + 1)
			end
			local at = tokens[d.open].last
			return text:sub(1, at) .. " default = " .. literal(value) .. "," .. text:sub(at + 1)
		end
	end
	return nil, "no top-level param " .. tostring(name)
end

return Params
