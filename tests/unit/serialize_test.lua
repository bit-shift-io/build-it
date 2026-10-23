-- The serializer (src/game/script/serialize.lua) and lock check
-- (src/game/script/lockcheck.lua): a declarative design script's node tree
-- written back as formatted Lua that runs to the same tree, and a script
-- holding code the serializer can't regenerate marked locked.
local Sandbox = require("src.game.script.sandbox")
local Serialize = require("src.game.script.serialize")

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

local function run(text)
	return assert(Sandbox.run(text, "design")).root
end

local DESIGN = [[
return group{ id = "root", name = "House",
	box{ id = "base", name = "Base", size = { 2, 1.5, 0.1 } },
	sphere{ id = "dome", radius = 0.6,
		transform = { move = { 1, 0.75, 1 }, rotate = { 0, 0, 45 }, scale = 1.4 } },
	group{ id = "inner", box{ id = "post", size = { 0.30000000000000004, 0.25, 2 } } },
	role{ id = "saw", ability = "saw", transform = { move = { 0.5, 0.5, 0 } } },
	prefab("input_port", { id = "in", name = "Door", transform = { move = { 0, 1, 0 } } }),
}
]]

test("a tree serialized and run again is the same tree, ids and names kept", function()
	local root = run(DESIGN)
	local again = run(Serialize.tree(root))
	assertTrue(same(root, again), Serialize.tree(root))
	assertEqual("dome", again.children[2].id)
	assertEqual("Door", again.children[5].name)
end)

test("the text is formatted with sorted keys, one child per line, and names as name = \"...\"", function()
	local root = run([[return group{ name = "House", id = "root",
		box{ size = { 2, 1, 1 }, name = "Base", id = "base", transform = { scale = 2, move = { 0.1, 0, 0 } } },
		prefab("bed"), group{} }]])
	assertEqual([[
return group{ id = "root", name = "House",
	box{ id = "base", name = "Base", size = { 2, 1, 1 }, transform = { move = { 0.1, 0, 0 }, scale = { 2, 2, 2 } } },
	prefab("bed"),
	group{},
}
]], Serialize.tree(root))
end)

local Lockcheck = require("src.game.script.lockcheck")

test("a declarative script is not locked, and its tree comes with the check", function()
	local result = assert(Lockcheck.check(DESIGN, "design"))
	assertFalse(result.locked)
	assertEqual("root", result.root.id)
end)

test("a script building its nodes in a loop is locked", function()
	local result = assert(Lockcheck.check([[
		local posts = {}
		for i = 1, 3 do
			posts[i] = box{ id = "post" .. i, transform = { move = { i, 0, 0 } } }
		end
		return group{ id = "root", unpack(posts) }
	]], "design"))
	assertTrue(result.locked)
	assertEqual(3, #result.root.children)
end)

test("params, locals, functions and maths lock a script; comments and negative numbers don't", function()
	local function locked(text)
		return assert(Lockcheck.check(text, "design")).locked
	end
	assertTrue(locked('local h = UI.number({ default = 1 })\nreturn box{ size = { 1, 1, h } }'))
	assertTrue(locked('local function post() return box{} end\nreturn group{ post(), post() }'))
	assertTrue(locked('return box{ size = { 2 * 1, 1, 1 } }'))
	assertTrue(locked('return box{ id = "a" .. "b" }'))
	assertFalse(locked('-- a post\nreturn box{ id = "post", --[[ moved ]] transform = { move = { -1, -0.5, 1e-3 } } }'))
end)

test("a script that fails gives its error instead of a check", function()
	local result, message = Lockcheck.check("return 1", "broken")
	assertEqual(nil, result)
	assertTrue(message:find("broken", 1, true) ~= nil, message)
end)

test("cylinders, cones and wedges round-trip and leave a script unlocked", function()
	local text = [[
return group{ id = "root",
	cylinder{ id = "post", radius = 0.25, height = 2, segments = 12 },
	cone{ id = "spire", radius = 0.5, height = 1.5, segments = 8, transform = { move = { 0, 0, 2 } } },
	wedge{ id = "ramp", size = { 2, 1, 0.5 } },
	sphere{ id = "ball", radius = 0.5, segments = 16 },
}
]]
	local root = run(text)
	assertTrue(same(root, run(Serialize.tree(root))), Serialize.tree(root))
	assertFalse(assert(Lockcheck.check(text, "design")).locked)
end)

test("a shape keeps its points and plane frame through a save, and stays editable", function()
	local text = [[
return group{ id = "root",
	shape{ id = "s", points = { { 0, 0 }, { 2, 0 }, { 1, 2, -1, 0.5 } },
		plane = { origin = { 0, 0, 1 }, u = { 1, 0, 0 }, v = { 0, 0, 1 } } },
	shape{ id = "g", points = { { 0, 0 }, { 1, 0 }, { 1, 1 } } },
}
]]
	local result = assert(Lockcheck.check(text, "design"))
	assertFalse(result.locked, "a declarative shape is editable")
	local s = result.root.children[1]
	assertEqual("shape", s.kind)
	assertEqual(0.5, s.points[3][4])
	assertEqual("0 0 1", table.concat(s.plane.v, " "))
	local g = result.root.children[2]
	assertEqual("0 0 0", table.concat(g.plane.origin, " "), "no plane means the ground")
	local again = assert(Lockcheck.check(Serialize.tree(result.root), "design"))
	assertFalse(again.locked)
	assertTrue(same(result.root, again.root), "same tree after a save")
end)

test("a shape whose outline crosses itself or has a bad point fails with why", function()
	local _, why = Sandbox.run('return shape{ points = { { 0, 0 }, { 2, 2 }, { 2, 0 }, { 0, 2 } } }', "design")
	assertTrue(why:find("shape outline crosses itself", 1, true) ~= nil, why)
	_, why = Sandbox.run('return shape{ points = { { 0, 0 }, { 2, "a" }, { 2, 2 } } }', "design")
	assertTrue(why:find("shape point 2 must be 2 or 4 numbers", 1, true) ~= nil, why)
	_, why = Sandbox.run('return shape{ points = { { 0, 0 }, { 1, 0 }, { 1, 1 } }, plane = { u = { 1, 0, 0 }, v = { 2, 0, 0 } } }', "design")
	assertTrue(why:find("shape plane u and v must not be parallel", 1, true) ~= nil, why)
end)

test("every node kind keeps its material through a save and stays editable", function()
	local m = 'material = { name = "stone", rotation = 15, scale = 0.5, variant = "brick" }'
	local text = [[
return group{ id = "root", ]] .. m .. [[,
	box{ id = "b", material = { name = "plank", variant = "logs" } },
	sphere{ id = "s", ]] .. m .. [[ },
	extrude{ id = "e", height = 1, ]] .. m .. [[,
		shape{ id = "sh", points = { { 0, 0 }, { 1, 0 }, { 1, 1 } } },
	},
	role{ id = "r", ability = "saw", ]] .. m .. [[ },
	prefab("input_port", { id = "in", ]] .. m .. [[ }),
}
]]
	local result = assert(Lockcheck.check(text, "design"))
	assertFalse(result.locked, "a declarative script with materials is editable")
	local root = result.root
	assertEqual("brick", root.material.variant)
	assertEqual("logs", root.children[1].material.variant)
	assertEqual(1, root.children[1].material.scale)
	assertEqual("stone", root.children[5].material.name)
	assertTrue(same(root, run(Serialize.tree(root))), Serialize.tree(root))
end)

test("an unknown material or variant is a script error that lists the choices", function()
	local _, message = Sandbox.run('return box{ material = { name = "gold" } }', "design")
	assertTrue(message and message:find("plank, stone", 1, true), message)
	_, message = Sandbox.run('return box{ material = { name = "plank", variant = "brick" } }', "design")
	assertTrue(message and message:find("polished, bark, shingles, logs", 1, true), message)
end)

test("a node colour round trips as an RGB literal or a team slot and stays editable", function()
	local text = [[
return group{ id = "root", color = "primary",
	box{ id = "roof", color = "secondaryDark" },
	box{ id = "wall", color = { 0.25, 0.5, 1 } },
	prefab("input_port", { id = "in", color = "highlight" }),
}
]]
	local result = assert(Lockcheck.check(text, "design"))
	assertFalse(result.locked, "a declarative script with colours is editable")
	local root = result.root
	assertEqual("primary", root.color)
	assertEqual("secondaryDark", root.children[1].color)
	assertEqual(0.5, root.children[2].color[2])
	assertEqual("highlight", root.children[3].color)
	assertTrue(same(root, run(Serialize.tree(root))), Serialize.tree(root))
end)

test("an unknown slot or a bad RGB colour is a script error", function()
	local _, message = Sandbox.run('return box{ color = "purple" }', "design")
	assertTrue(message and message:find("primary, primaryDark", 1, true), message)
	_, message = Sandbox.run("return box{ color = { 0.5, 2, 0 } }", "design")
	assertTrue(message and message:find("0 to 1", 1, true), message)
	_, message = Sandbox.run("return box{ color = { 0.5, 0.5 } }", "design")
	assertTrue(message and message:find("color", 1, true), message)
end)
