-- The design library (src/game/designs/library.lua): design and prefab
-- scripts by name, the player's shadowing the built-ins, and the designs
-- the building picker offers.
local Library = require("src.game.designs.library")
local Resolve = require("src.game.script.resolve")
local Builtins = require("src.game.designs.builtins")
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

-- The built-ins with the storage facility as the only design (the starter
-- buildings have their own test, tests/unit/starter_content_test.lua).
local facilityOnly = { designs = { storage_facility = builtins.designs.storage_facility }, prefabs = builtins.prefabs }

test("the picker offers the designs with a function role, by name, each compiled", function()
	local lib = Library.merge(facilityOnly, { designs = { shed = SHED, mill = MILL } })
	local entries = Library.placeable(lib, Config)
	assertEqual("mill,storage_facility", names(entries))
	local mill = entries[1].blueprint
	assertEqual(2, mill.width)
	assertEqual("saw", mill.roles.abilities[1].ability)
	assertTrue(mill.cost.plank > 0, "it carries its voxel cost")
end)

test("a design that fails to compile or has a problem is not offered", function()
	local bench = [[return group{ box{}, prefab("sawbench") }]]
	local lib = Library.merge(facilityOnly, { designs = { broken = "return group{", loop = 'return prefab("loop")', bench = bench } })
	lib.prefabs.loop = 'return prefab("loop")'
	assertEqual("storage_facility", names(Library.placeable(lib, Config)))
end)

test("a saved design shadowing a built-in is offered in its place", function()
	local lib = Library.merge(facilityOnly, { designs = { storage_facility = MILL } })
	local entries = Library.placeable(lib, Config)
	assertEqual("storage_facility", names(entries))
	assertEqual("saw", entries[1].blueprint.roles.abilities[1].ability)
end)

local LAMP = [[return box{ size = { 1, 1, 0.5 } }]]
local HOUSE = [[return group{ box{ size = { 2, 2, 1 } }, prefab("lamp") }]]

test("renaming a prefab moves its script and updates nothing that references it", function()
	local lib = Library.merge(builtins, { designs = { house = HOUSE }, prefabs = { lamp = LAMP } })
	local renamed = assert(Library.rename(lib, "prefabs", "lamp", "torch"))
	assertEqual(LAMP, renamed.prefabs.torch)
	assertEqual(nil, renamed.prefabs.lamp)
	assertEqual(HOUSE, renamed.designs.house, "the house still says lamp")
	assertEqual(LAMP, lib.prefabs.lamp, "the library given is untouched")
end)

test("a design placing a renamed prefab fails to load with an error naming the missing prefab", function()
	local lib = Library.merge(builtins, { designs = { house = HOUSE }, prefabs = { lamp = LAMP } })
	local renamed = assert(Library.rename(lib, "prefabs", "lamp", "torch"))
	local resolved, message = Resolve.design(renamed.designs.house, "house", renamed)
	assertEqual(nil, resolved)
	assertTrue(message:find('prefab "lamp"', 1, true), message)
	assertTrue(message:find("deleted or renamed", 1, true), message)
end)

test("a rename is refused for a built-in, a missing script, a bad name or a taken one", function()
	local lib = Library.merge(builtins, { designs = { house = HOUSE, shed = SHED }, prefabs = { lamp = LAMP } })
	for _, case in ipairs({
		{ "designs", "storage_facility", "depot", "built-in" },
		{ "designs", "nope", "other", "no design" },
		{ "designs", "house", "my house", "letters" },
		{ "designs", "house", "shed", "already" },
		{ "prefabs", "lamp", "saw", "already" },
	}) do
		local out, why = Library.rename(lib, case[1], case[2], case[3])
		assertEqual(nil, out, case[2] .. " -> " .. case[3])
		assertTrue(why:find(case[4], 1, true), why)
	end
end)

test("duplicating copies a script, a built-in too, under the first free copy name", function()
	local lib = Library.merge(builtins, { designs = { house = HOUSE, house_copy = SHED }, prefabs = {} })
	local name = Library.copyName(lib, "designs", "house")
	assertEqual("house_copy2", name)
	local out = assert(Library.duplicate(lib, "designs", "house", name))
	assertEqual(HOUSE, out.designs.house_copy2)
	assertEqual(HOUSE, out.designs.house, "the original stays")
	assertEqual(nil, lib.designs.house_copy2, "the library given is untouched")
	local saw = assert(Library.duplicate(lib, "prefabs", "saw", Library.copyName(lib, "prefabs", "saw")))
	assertEqual(builtins.prefabs.saw, saw.prefabs.saw_copy)
	local taken, why = Library.duplicate(lib, "designs", "house", "house_copy")
	assertEqual(nil, taken)
	assertTrue(why:find("already", 1, true), why)
end)

test("deleting drops a saved script; a built-in can't be deleted", function()
	local lib = Library.merge(builtins, { designs = { house = HOUSE }, prefabs = { lamp = LAMP } })
	local out = assert(Library.delete(lib, "prefabs", "lamp"))
	assertEqual(nil, out.prefabs.lamp)
	assertEqual(LAMP, lib.prefabs.lamp, "the library given is untouched")
	local _, message = Resolve.design(out.designs.house, "house", out)
	assertTrue(message:find('prefab "lamp"', 1, true), message)
	local refused, why = Library.delete(lib, "prefabs", "saw")
	assertEqual(nil, refused)
	assertTrue(why:find("built-in", 1, true), why)
	assertEqual(nil, (Library.delete(lib, "designs", "nope")))
end)

test("the manager lists a kind's scripts by name, built-ins marked", function()
	local lib = Library.merge(builtins, { designs = { house = HOUSE, barn = SHED }, prefabs = { lamp = LAMP } })
	local designs = Library.entries(lib, "designs")
	assertEqual(#Builtins.DESIGNS + 2, #designs)
	assertEqual("barn", designs[1].name)
	assertEqual(false, designs[1].builtin)
	assertEqual(true, designs[#designs].builtin)
	local prefabs = Library.entries(lib, "prefabs")
	assertEqual(#Builtins.prefabNames() + 1, #prefabs)
end)
