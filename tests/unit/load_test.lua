-- A villager's load (docs/CONTEXT.md "Load"): the items it carries, one
-- kind at a time, never more than config.villagers.carryLimit.
local Load = require("src.game.components.load")
local Config = require("src.game.config")

test("a load takes items up to the carry limit, one kind at a time", function()
	local load = Load.new(Config)
	assertTrue(Load.empty(load))
	assertEqual(Config.villagers.carryLimit, Load.room(load))

	Load.add(load, "log", 1)
	assertEqual("log", load.item)
	assertEqual(1, load.count)
	assertEqual(Config.villagers.carryLimit - 1, Load.room(load))
	assertFalse(Load.empty(load))

	assertFalse(pcall(Load.add, load, "plank", 1), "a second kind is refused")
	assertFalse(pcall(Load.add, load, "log", Load.room(load) + 1), "the carry limit caps it")
end)

test("removing the last item empties the load", function()
	local load = Load.new(Config)
	Load.add(load, "log", 2)
	Load.remove(load, 2)
	assertTrue(Load.empty(load))
	assertEqual(nil, load.item)
	Load.add(load, "plank", 1)
	assertEqual("plank", load.item)
end)
