-- The lock check (docs/CONTEXT.md "Locked script"): whether the builder
-- may rewrite a design script from its node tree. Pure; plain LuaJIT.
--
-- A script is declarative, and so editable in the builder, when it is
-- nothing but `return` and node calls with literal fields (the shape
-- src/game/script/serialize.lua writes) and serializing its tree runs back
-- to the same tree. Anything else -- locals, loops, functions, maths,
-- params -- is code the serializer can't regenerate: the script is locked,
-- and saving must never overwrite it.
local Sandbox = require("src.game.script.sandbox")
local Serialize = require("src.game.script.serialize")
local Lex = require("src.game.script.lex")

local Lockcheck = {}

-- The names a declarative script may call.
local NODE_CALLS = {
	box = true,
	sphere = true,
	cylinder = true,
	cone = true,
	wedge = true,
	group = true,
	role = true,
	prefab = true,
	shape = true,
	extrude = true,
	lathe = true,
	path = true,
	sweep = true,
}
-- The keywords a declarative script may use.
local LITERALS = { ["return"] = true, ["true"] = true, ["false"] = true, ["nil"] = true }
-- Punctuation of table constructors and calls.
local PUNCTUATION = { ["{"] = true, ["}"] = true, ["("] = true, [")"] = true, [","] = true, [";"] = true }

-- Whether `text` holds only what the serializer writes: literal fields in
-- node calls under one `return`.
local function declarative(text)
	local list = Lex.tokens(text)
	for i, t in ipairs(list) do
		local nextToken = list[i + 1] or {}
		if t.kind == "name" then
			local isKey = nextToken.text == "="
			if not (LITERALS[t.text] or NODE_CALLS[t.text] or isKey) then
				return false
			end
		elseif t.kind == "symbol" then
			local isKey = t.text == "=" and (list[i - 1] or {}).kind == "name"
			local isSign = t.text == "-" and nextToken.kind == "number"
			if not (PUNCTUATION[t.text] or isKey or isSign) then
				return false
			end
		end
	end
	return true
end

-- Whether a and b hold the same values, tables compared by content.
local function same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in pairs(a) do
		if not same(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

-- Runs design script `text` (named `name` in messages) through the sandbox
-- and checks whether the builder may regenerate it. Returns Sandbox.run's
-- { root, params } with locked = true | false, or nil and the script's
-- error.
function Lockcheck.check(text, name)
	local result, message = Sandbox.run(text, name)
	if not result then
		return nil, message
	end
	result.locked = true
	if #result.params == 0 and declarative(text) then
		local again = Sandbox.run(Serialize.tree(result.root), name)
		result.locked = not (again and same(result.root, again.root))
	end
	return result
end

return Lockcheck
