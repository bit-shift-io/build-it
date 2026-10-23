-- Runs a design script (docs/CONTEXT.md "Design script", ADR 0006). The
-- only way any design or prefab text becomes code: nothing else may call
-- load, loadstring or dofile on one.
--
-- The script sees a fixed environment: the node API (src/game/script/api.lua)
-- and a few safe standard functions. No os, io, require, load, debug,
-- getfenv/setfenv, metatables, coroutines or pcall. Text only: bytecode
-- never loads. An instruction budget stops runaway scripts.
local Api = require("src.game.script.api")

local Sandbox = {}

-- Instructions a script may run before it is stopped.
Sandbox.BUDGET = 5000000

-- How often, in instructions, the budget is checked.
local CHECK_EVERY = 1000

-- string.rep's largest result, so a script can't exhaust memory in one call.
local MAX_REP = 100000

local BUDGET_MESSAGE = "script ran too long (instruction budget used up)"

-- The string library a script sees. Pattern functions (find, match,
-- gmatch, gsub) are left out: their matching runs in C, beyond the budget.
local function stringLibrary()
	local s = {}
	for _, name in ipairs({ "byte", "char", "format", "len", "lower", "upper", "sub", "reverse" }) do
		s[name] = string[name]
	end
	function s.rep(text, n, sep)
		if type(n) == "number" and #tostring(text) * n > MAX_REP then
			error("string.rep result too long", 2)
		end
		return string.rep(text, n, sep)
	end
	return s
end

local function copy(t)
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	return out
end

local function environment(functions, strings)
	local env = {
		math = copy(math),
		string = strings,
		table = { insert = table.insert, remove = table.remove, concat = table.concat, sort = table.sort },
		ipairs = ipairs,
		pairs = pairs,
		next = next,
		select = select,
		type = type,
		tostring = tostring,
		tonumber = tonumber,
		unpack = unpack,
		error = error,
		assert = assert,
	}
	for k, v in pairs(functions) do
		env[k] = v
	end
	return env
end

-- Runs `chunk` under the instruction budget, with the string metatable
-- pointing at `strings` so ("").method can't reach the real library.
local function guarded(chunk, budget, strings)
	local used = 0
	local stringMeta = getmetatable("")
	local realIndex = stringMeta.__index
	local oldHook, oldMask, oldCount = debug.gethook()
	-- Count hooks never fire inside JIT traces; interpret the script.
	jit.off(chunk, true)
	stringMeta.__index = strings
	debug.sethook(function()
		used = used + CHECK_EVERY
		if used > budget then
			error(BUDGET_MESSAGE, 2)
		end
	end, "", CHECK_EVERY)
	local ok, result = pcall(chunk)
	debug.sethook(oldHook, oldMask, oldCount)
	stringMeta.__index = realIndex
	return ok, result
end

-- Runs design script `text`, named `name` in error messages. opts.budget
-- overrides Sandbox.BUDGET; opts.values gives params values by declaration
-- order (Api.new). Returns { root = <node>, params = { ... } }
-- (src/game/script/api.lua), or nil and a message with the script line.
function Sandbox.run(text, name, opts)
	opts = opts or {}
	local functions, state = Api.new(opts.values)
	local strings = stringLibrary()
	local chunk, err = load(text, "=" .. name, "t", environment(functions, strings))
	if not chunk then
		return nil, err
	end
	local ok, root = guarded(chunk, opts.budget or Sandbox.BUDGET, strings)
	if not ok then
		local message = tostring(root)
		-- An error raised in a tail-called API function has lost the
		-- script's line; name the script at least.
		if message:sub(1, #name + 1) ~= name .. ":" then
			message = name .. ": " .. message
		end
		return nil, message
	end
	if not state.isNode(root) then
		return nil, name .. ": the script must return a node, e.g. return box{}"
	end
	return { root = root, params = state.params }
end

-- The line of script `name` that error `message` (from Sandbox.run) points
-- at, or nil when it names none of that script's lines.
function Sandbox.errorLine(message, name)
	local prefix = name .. ":"
	if message:sub(1, #prefix) ~= prefix then
		return nil
	end
	return tonumber(message:sub(#prefix + 1):match("^(%d+):"))
end

return Sandbox
