-- The design library (src/game/designs/library.lua): design and prefab
-- scripts by name, the player's shadowing the built-ins, and the designs
-- the building picker offers.
local Library = require("src.game.designs.library")
local Config = require("src.game.config")
local builtins = require("tests.support.builtins")

test("a saved script shadows the built-in of the same name and kind", function()
	local base = { designs = { hut = "built-in hut", mill = "built-in mill" }, prefabs = { bed = "built-in bed" } }
	local saved = { designs = { hut = "my hut", shed = "my shed" }, prefabs = { bed = "my bed", lamp = "my lamp" } }
	local lib = Library.merge(base, saved)
	assertEqual("my hut", lib.designs.hut)
	assertEqual("built-in mill", lib.designs.mill)
	assertEqual("my shed", lib.designs.shed)
	assertEqual("my bed", lib.prefabs.bed)
	assertEqual("my lamp", lib.prefabs.lamp)
	assertEqual("built-in hut", base.designs.hut, "the built-ins are untouched")
end)

local SHED = [[return group{ box{ size = { 1, 1, 1 } } }]]
local MILL = [[return group{ box{ size = { 2, 1, 1 } }, prefab("saw", { transform = { move = { 0.25, 0.25, 0 } } }) }]]

local function names(entries)
	local out = {}
	for i, e in ipairs(entries) do
		out[i] = e.name
	end
	return table.concat(out, ",")
end

test("the picker offers the designs with a function role, by name, each compiled", function()
	local lib = Library.merge(builtins, { designs = { shed = SHED, mill = MILL } })
	local entries = Library.placeable(lib, Config)
	assertEqual("mill,storage_facility", names(entries))
	local mill = entries[1].blueprint
	assertEqual(2, mill.width)
	assertEqual("saw", mill.roles.abilities[1].ability)
	assertTrue(mill.cost.plank > 0, "it carries its voxel cost")
end)

test("a design that fails to compile or has a problem is not offered", function()
	local bench = [[return group{ box{}, prefab("sawbench") }]]
	local lib = Library.merge(builtins, { designs = { broken = "return group{", loop = 'return prefab("loop")', bench = bench } })
	lib.prefabs.loop = 'return prefab("loop")'
	assertEqual("storage_facility", names(Library.placeable(lib, Config)))
end)

test("a saved design shadowing a built-in is offered in its place", function()
	local lib = Library.merge(builtins, { designs = { storage_facility = MILL } })
	local entries = Library.placeable(lib, Config)
	assertEqual("storage_facility", names(entries))
	assertEqual("saw", entries[1].blueprint.roles.abilities[1].ability)
end)
