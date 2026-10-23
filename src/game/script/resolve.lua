-- Resolves a design script's references (docs/CONTEXT.md "Prefab", ADR
-- 0006): runs it through the sandbox, then every prefab("name") it places,
-- looked up by name in a library of script texts. Names only, never paths.
-- Pure; plain LuaJIT. `game` never reads files: the library's texts come
-- from `app` (or a test).
--
--   library = { prefabs = { [name] = <script text> } }
local Sandbox = require("src.game.script.sandbox")

local Resolve = {}

-- Raises `message` with no position.
local function fail(message)
	error(message, 0)
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
		local text = library.prefabs[name]
		if not text then
			fail("unknown prefab \"" .. name .. "\"")
		end
		local result, message = Sandbox.run(text, name)
		if not result then
			fail(message)
		end
		path[#path + 1] = name
		expand(result.root, library, path)
		path[#path] = nil
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
