-- The serializer (docs/CONTEXT.md "Design script", ADR 0006): a node tree
-- (src/game/script/api.lua) written as a declarative design script, the
-- file the builder saves. Pure; plain LuaJIT.
--
-- The text runs through the sandbox back to the same tree: every field the
-- API keeps is written, numbers with enough digits to read back exactly,
-- and table keys sorted so a file changes only where the tree did.
--
--   return group{ id = "root", name = "House",
--   	box{ id = "base", size = { 2, 1.5, 1 } },
--   	prefab("bed", { id = "bed", transform = { move = { 1, 0, 0 } } }),
--   }
local Serialize = {}

local INDENT = "\t"

-- `x` in the fewest digits that read back as exactly `x`.
local function number(x)
	for digits = 14, 17 do
		local s = string.format("%." .. digits .. "g", x)
		if tonumber(s) == x then
			return s
		end
	end
	error("can't write number " .. tostring(x))
end

local function sortedKeys(t)
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	return keys
end

-- A field value: a string, a number, a list ({ 1, 2, 3 }) or a record with
-- name keys ({ move = { ... } }), keys sorted.
local function value(v)
	if type(v) == "string" then
		return string.format("%q", v)
	elseif type(v) == "number" then
		return number(v)
	elseif type(v) == "boolean" then
		return tostring(v)
	end
	assert(type(v) == "table", "can't write a " .. type(v))
	local parts = {}
	if #v > 0 then
		for i, item in ipairs(v) do
			parts[i] = value(item)
		end
	else
		for _, k in ipairs(sortedKeys(v)) do
			parts[#parts + 1] = k .. " = " .. value(v[k])
		end
	end
	if #parts == 0 then
		return "{}"
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

-- `node`'s fields other than its children, as { "key = value", ... } in
-- key order: role fields sit beside the others, an empty transform is left
-- out, and kind and prefab name are written outside the table.
local function fields(node)
	local flat = {}
	for k, v in pairs(node) do
		if k ~= "kind" and k ~= "children" and k ~= "role" and k ~= "prefab" then
			flat[k] = v
		end
	end
	for k, v in pairs(node.role or {}) do
		flat[k] = v
	end
	if flat.transform and next(flat.transform) == nil then
		flat.transform = nil
	end
	local out = {}
	for _, k in ipairs(sortedKeys(flat)) do
		out[#out + 1] = k .. " = " .. value(flat[k])
	end
	return out
end

-- `node` as script text at indent `depth`, without the trailing comma.
local function write(node, depth)
	local own = fields(node)
	if node.kind == "prefab" and #own == 0 then
		return string.format("prefab(%q)", node.prefab)
	elseif node.kind == "prefab" then
		return string.format("prefab(%q, { %s })", node.prefab, table.concat(own, ", "))
	end
	local list = table.concat(own, ", ")
	local children = node.children or {}
	if #children == 0 then
		return #own > 0 and node.kind .. "{ " .. list .. " }" or node.kind .. "{}"
	end
	local lines = { node.kind .. "{" .. (#own > 0 and " " .. list .. "," or "") }
	local pad = string.rep(INDENT, depth + 1)
	for _, child in ipairs(children) do
		lines[#lines + 1] = pad .. write(child, depth + 1) .. ","
	end
	lines[#lines + 1] = string.rep(INDENT, depth) .. "}"
	return table.concat(lines, "\n")
end

-- The tree under `root` as a design script's text.
function Serialize.tree(root)
	return "return " .. write(root, 0) .. "\n"
end

return Serialize
