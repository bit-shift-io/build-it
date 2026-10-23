-- The design script sandbox (ADR 0006, docs/CONTEXT.md "Design script"):
-- a script runs with a fixed API and returns a node tree. Nothing outside
-- the API is reachable, a runaway script stops at its instruction budget,
-- and errors carry the script's line.
local Sandbox = require("src.game.script.sandbox")

-- Runs `text` and fails the test unless it errors; returns the message.
local function fails(text, opts)
	local result, err = Sandbox.run(text, "design", opts)
	assertEqual(nil, result, "expected the script to fail")
	assertEqual("string", type(err))
	return err
end

local function contains(haystack, needle)
	return haystack:find(needle, 1, true) ~= nil
end

test("a script returning a box gives its node", function()
	local result = assert(Sandbox.run('return box{ id = "base", name = "Base", size = { 2, 1, 3 } }', "design"))
	local root = result.root
	assertEqual("box", root.kind)
	assertEqual("base", root.id)
	assertEqual("Base", root.name)
	assertEqual(2, root.size[1])
	assertEqual(3, root.size[3])
end)

test("os, io, require, the loaders, debug, setfenv and getmetatable are all unavailable", function()
	for _, name in ipairs({
		"os",
		"io",
		"require",
		"load",
		"loadstring",
		"loadfile",
		"dofile",
		"debug",
		"setfenv",
		"getfenv",
		"getmetatable",
		"setmetatable",
		"rawget",
		"rawset",
		"coroutine",
		"pcall",
		"xpcall",
		"jit",
		"package",
		"collectgarbage",
		"newproxy",
		"_G",
	}) do
		local result = assert(Sandbox.run("return box{ name = type(" .. name .. ") }", "design"))
		assertEqual("nil", result.root.name, name .. " should be unavailable")
	end
end)

test("string.dump is unavailable, through the library and through a string's methods", function()
	local result = assert(Sandbox.run('return box{ name = type(string.dump) .. type(("").dump) }', "design"))
	assertEqual("nilnil", result.root.name)
end)

test("a string's methods are the sandboxed library during the run and the real one after", function()
	local result = assert(Sandbox.run('return box{ name = ("ab"):upper() .. type(("").find) }', "design"))
	assertEqual("ABnil", result.root.name)
	assertEqual("function", type(("").find))
	assertEqual("function", type(("").dump))
end)

test("getmetatable on a string fails", function()
	fails('local m = getmetatable("") return box{}')
end)

test("_G lookups fail", function()
	local err = fails("local os = _G.os return box{}")
	assertTrue(contains(err, "_G"), err)
end)

test("bytecode never loads", function()
	local bytecode = string.dump(function()
		return 1
	end)
	fails(bytecode)
end)

test("an infinite loop fails with a budget error", function()
	local err = fails("while true do end", { budget = 100000 })
	assertTrue(contains(err, "budget"), err)
end)

test("an infinite loop inside a function and a hot inner loop both stop", function()
	local err = fails("local function f() local n = 0 for i = 1, 1e12 do n = n + i end end f()", { budget = 100000 })
	assertTrue(contains(err, "budget"), err)
end)

test("the budget hook is gone after a run", function()
	fails("while true do end", { budget = 10000 })
	assertEqual(nil, debug.gethook())
end)

test("a syntax error reports its line", function()
	local err = fails("local a = 1\nlocal b = 2\nlocal = 3\nreturn box{}")
	assertTrue(contains(err, "design:3:"), err)
end)

test("a runtime error in an API call reports the script's line", function()
	-- Not a tail call: `return box{...}` drops the script's frame, and the
	-- message then names only the script.
	local err = fails('local a = 1\nlocal b = box{ size = "big" }\nreturn b')
	assertTrue(contains(err, "design:2:"), err)
	assertTrue(contains(err, "size"), err)
end)

test("an API error in a tail call still names the script", function()
	local err = fails('return box{ size = "big" }')
	assertEqual(1, err:find("design: ", 1, true), err)
end)

test("a script that returns no node fails", function()
	fails("return 3")
end)

test("string.rep can't build a huge string", function()
	fails('local s = string.rep("x", 1e9) return box{}')
end)

test("a script changing math does not change the host's math", function()
	assert(Sandbox.run("math.floor = nil return box{}", "design"))
	assertEqual("function", type(math.floor))
end)

test("groups hold children, spheres a radius, and nodes a transform", function()
	local result = assert(Sandbox.run(
		[[
return group{ id = "root",
	box{ id = "a", transform = { move = { 1, 2, 3 }, rotate = { 0, 0, 90 }, scale = 2 } },
	sphere{ id = "b", radius = 1.5 },
}]],
		"design"
	))
	local root = result.root
	assertEqual("group", root.kind)
	assertEqual(2, #root.children)
	local a, b = root.children[1], root.children[2]
	assertEqual(2, a.transform.move[2])
	assertEqual(90, a.transform.rotate[3])
	assertEqual(2, a.transform.scale[3])
	assertEqual("sphere", b.kind)
	assertEqual(1.5, b.radius)
end)

test("a group child must be a node", function()
	fails('return group{ { kind = "box" } }')
end)

test("UI.number declares a param and returns its default", function()
	local result = assert(Sandbox.run("local r = UI.number({ default = 3, step = 0.2 }) return sphere{ radius = r }", "design"))
	assertEqual(3, result.root.radius)
	assertEqual(1, #result.params)
	assertEqual("number", result.params[1].kind)
	assertEqual(0.2, result.params[1].step)
end)
