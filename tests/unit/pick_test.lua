-- Picking (src/game/geometry/pick.lua): which node of a resolved design
-- tree a ray from the builder's camera hits first.
local Resolve = require("src.game.script.resolve")
local Pick = require("src.game.geometry.pick")
local library = require("tests.support.builtins")

local function targetsOf(text)
	return Pick.targets(assert(Resolve.design(text, "design", library)).root)
end

local ROW = [[
return group{ id = "root", transform = { move = { 1, 0, 0 } },
	box{ id = "near", size = { 1, 1, 1 } },
	box{ id = "far", size = { 1, 1, 1 }, transform = { move = { 0, 3, 0 } } },
}
]]

test("a ray hits the nearest node along it, with every transform above it applied", function()
	local targets = targetsOf(ROW)
	-- Looking south from y = -5 through x = 1.5, z = 0.5: near first, then far.
	assertEqual("near", (Pick.at(targets, { 1.5, -5, 0.5 }, { 0, 1, 0 })))
	assertEqual("far", (Pick.at(targets, { 1.5, 10, 0.5 }, { 0, -1, 0 })))
	assertEqual(nil, (Pick.at(targets, { 0.5, -5, 0.5 }, { 0, 1, 0 })))
end)

test("anything inside a prefab instance picks as the instance", function()
	local targets = targetsOf([[return group{ id = "root",
		prefab("bed", { id = "cot", transform = { move = { 4, 0, 0 } } }) }]])
	assertEqual(1, #targets)
	assertEqual("cot", targets[1].id)
end)
