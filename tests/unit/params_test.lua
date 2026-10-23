-- Params (docs/CONTEXT.md "Param"): the UI.* values a design script
-- declares, named after their variables, clamped to their ranges, and a
-- default rewritten in the script's text as the one surgical edit.
local Sandbox = require("src.game.script.sandbox")
local Params = require("src.game.script.params")

-- The params `text` declares, collected.
local function collect(text)
	local result = assert(Sandbox.run(text, "design"))
	return Params.collect(text, result.params)
end

test("params are collected in declaration order, labelled by variable name", function()
	local params = collect([[
local radius = UI.number({ default = 3, step = 0.2 })
local open = UI.bool{ default = true }
local roof = UI.choice({ options = { "flat", "gable" }, default = "gable" })
local tint = UI.color({ label = "Tint colour", default = { 1, 0, 0 } })
return sphere{ radius = radius }
]])
	assertEqual(4, #params)
	assertEqual("radius", params[1].name)
	assertEqual("radius", params[1].label)
	assertEqual("number", params[1].kind)
	assertEqual(3, params[1].value)
	assertEqual("open", params[2].name)
	assertEqual(true, params[2].value)
	assertEqual("roof", params[3].name)
	assertEqual("gable", params[3].value)
	assertEqual("tint", params[4].name)
	assertEqual("Tint colour", params[4].label)
	assertEqual(0, params[4].value[2])
end)

test("out-of-range values clamp to the param's range", function()
	local params = collect("local n = UI.number({ default = 9, min = 1, max = 5 })\nreturn box{}")
	assertEqual(5, params[1].value)
	assertEqual(1, Params.clamp(params[1], -3))
	assertEqual(2.5, Params.clamp(params[1], 2.5))
	local tint = collect("local c = UI.color({ default = { 2, 0.5, -1 } })\nreturn box{}")[1]
	assertEqual(1, tint.value[1])
	assertEqual(0.5, tint.value[2])
	assertEqual(0, tint.value[3])
	assertEqual(nil, (Params.clamp({ kind = "choice", options = { "a" } }, "b")))
	assertEqual(nil, (Params.clamp({ kind = "bool" }, 1)))
end)

test("a bad param declaration fails with a message", function()
	local _, err = Sandbox.run("local c = UI.choice({ options = {} })\nreturn box{}", "design")
	assertTrue(err:find("design:1:", 1, true) ~= nil, err)
	_, err = Sandbox.run('local c = UI.choice({ options = { "a" }, default = "b" })\nreturn box{}', "design")
	assertTrue(err:find("one of the options", 1, true) ~= nil, err)
end)

local LOCKED = [[
-- A dome on legs. Comments, spacing and code stay as written.
local radius = UI.number({ default = 3, step = 0.2 }) -- the dome
local legs = UI.number{ step = 1, min = 3 }
local function leg(i)
	local radius = UI.number({ default = 7 })
	return box{ transform = { rotate = { 0, 0, i * 360 / legs } } }
end
local parts = {}
for i = 1, legs do parts[#parts + 1] = leg(i) end
parts[#parts + 1] = sphere{ radius = radius, transform = { move = { 0, 0, 2 } } }
return group(parts)
]]

test("a default is rewritten in a locked file without other changes", function()
	local text = assert(Params.rewrite(LOCKED, "radius", 4.4))
	assertEqual((LOCKED:gsub("default = 3,", "default = 4.4,")), text)
	local params = collect(text)
	assertEqual(4.4, params[1].value)
	assertEqual("radius", params[1].name)
end)

test("a param without a default gets one added; an unknown name is refused", function()
	local text = assert(Params.rewrite(LOCKED, "legs", 5))
	assertEqual((LOCKED:gsub("UI.number{ step = 1", "UI.number{ default = 5, step = 1")), text)
	assertEqual(5, collect(text)[2].value)
	local none, why = Params.rewrite(LOCKED, "parts", 1)
	assertEqual(nil, none)
	assertTrue(why:find("parts", 1, true) ~= nil, why)
end)

test("bool, choice and colour defaults are written as literals", function()
	local text = 'local roof = UI.choice({ options = { "flat", "gable" }, default = "flat" })\n'
		.. "local tint = UI.color({ default = { 1, 0, 0 } })\nlocal open = UI.bool({})\nreturn box{}\n"
	text = assert(Params.rewrite(text, "roof", "gable"))
	text = assert(Params.rewrite(text, "tint", { 0.5, 0.25, 1 }))
	text = assert(Params.rewrite(text, "open", true))
	local params = collect(text)
	assertEqual("gable", params[1].value)
	assertEqual(0.25, params[2].value[2])
	assertEqual(true, params[3].value)
end)

test("stepping a number moves it by its step, clamped, without float noise", function()
	local radius = collect("local radius = UI.number({ default = 3, step = 0.2, max = 3.3 })\nreturn box{}")[1]
	assertEqual(3.2, Params.step(radius, 1))
	assertEqual(2.8, Params.step(radius, -1))
	radius.value = 3.2
	assertEqual(3.3, Params.step(radius, 1))
	local count = collect("local n = UI.number({ default = 2 })\nreturn box{}")[1]
	assertEqual(3, Params.step(count, 1))
end)
