-- Resolves a design script's references (docs/CONTEXT.md "Prefab", ADR
-- 0006): runs it through the sandbox, then every prefab("name") it places,
-- looked up by name in a library of script texts. Names only, never paths.
-- Pure; plain LuaJIT. `game` never reads files: the library's texts come
-- from `app` (or a test).
--
--   library = { prefabs = { [name] = <script text> } }
--
-- An instance is one node with param overrides (prefab("bed", { params =
-- { width = 2 } })): its prefab runs with those values in place of the
-- defaults. Its material and colour, when it has them, apply to everything
-- in it, over the prefab's own.
local Sandbox = require("src.game.script.sandbox")
local Params = require("src.game.script.params")

local Resolve = {}

-- Raises `message` with no position.
local function fail(message)
	error(message, 0)
end

-- Runs prefab `name` from `library` with `overrides` ({ [param name] =
-- value }, or nil) in place of its params' defaults. Returns Sandbox.run's
-- { root, params } -- its own prefabs not yet resolved, params collected
-- (Params.collect: named, values as overridden) -- or nil and a message.
-- An override naming no param, or not fitting its param, is ignored.
function Resolve.prefab(library, name, overrides)
	local text = library.prefabs[name]
	if not text then
		return nil, "unknown prefab \"" .. tostring(name) .. "\": the library has none of that name (deleted or renamed?)"
	end
	local result, message = Sandbox.run(text, name)
	if not result then
		return nil, message
	end
	local params = Params.collect(text, result.params)
	if overrides and next(overrides) ~= nil then
		local values = {}
		for i, param in ipairs(params) do
			if param.name then
				values[i] = overrides[param.name]
			end
		end
		result, message = Sandbox.run(text, name, { values = values })
		if not result then
			return nil, message
		end
		params = Params.collect(text, result.params)
	end
	result.params = params
	return result
end

-- Sets `key` of `node` and every node under it to its own copy of `value`.
local function copy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		out[k] = copy(x)
	end
	return out
end

local function paint(node, key, value)
	node[key] = copy(value)
	for _, child in ipairs(node.children or {}) do
		paint(child, key, value)
	end
end

-- Fills every prefab node under `node` with its prefab's resolved root.
-- `path` lists the prefab names being resolved, outermost first; meeting
-- one of them again is a cycle.
local function expand(node, library, path)
	if node.kind == "prefab" then
		local name = node.prefab
		for i, open in ipairs(path) do
			if open == name then
				local names = { unpack(path, i) }
				names[#names + 1] = name
				fail("prefab cycle: " .. table.concat(names, " -> "))
			end
		end
		local result, message = Resolve.prefab(library, name, node.params)
		if not result then
			fail(message)
		end
		path[#path + 1] = name
		expand(result.root, library, path)
		path[#path] = nil
		if node.material then
			paint(result.root, "material", node.material)
		end
		if node.color then
			paint(result.root, "color", node.color)
		end
		node.children = { result.root }
		return
	end
	for _, child in ipairs(node.children or {}) do
		expand(child, library, path)
	end
end

-- Runs design script `text` (named `name` in messages) and resolves its
-- prefabs from `library`. Returns Sandbox.run's { root, params } with the
-- tree complete, or nil and a message.
function Resolve.design(text, name, library)
	local result, message = Sandbox.run(text, name)
	if not result then
		return nil, message
	end
	local ok, problem = pcall(expand, result.root, library, {})
	if not ok then
		return nil, name .. ": " .. tostring(problem)
	end
	return result
end

return Resolve
