-- Storage (src/game/components/storage.lua): a bounded item store, sized
-- from storage bricks and grown by the capacity trait.
local Storage = require("src.game.components.storage")
local Config = require("src.game.config")

local function traits(capacity)
	return { productivity = 0, capacity = capacity, reach = 0, health = 0 }
end

test("a store holds items up to its capacity, counting every item together", function()
	local s = Storage.new(3)
	Storage.add(s, "log")
	Storage.add(s, "stone")
	assertEqual(1, Storage.room(s))
	Storage.add(s, "log")
	assertEqual(0, Storage.room(s))
	assertEqual(3, Storage.total(s))
	assertFalse(pcall(Storage.add, s, "log"), "a full store refuses more")
end)

test("a building's storage is its storage bricks' sum, grown by capacity", function()
	local version = { bricks = { { storage = 8 }, { storage = 8 }, {} } }
	assertEqual(16, Storage.ofVersion(version, traits(0), Config).capacity)
	local grown = Storage.ofVersion(version, traits(10), Config).capacity
	assertEqual(math.floor(16 * (1 + 10 * Config.production.capacityStep)), grown)
	assertTrue(grown > 16)
	assertEqual(0, Storage.ofVersion({ bricks = { {} } }, traits(10), Config).capacity, "no storage brick, no storage")
end)

test("negative capacity never makes a store smaller than empty", function()
	assertEqual(0, Storage.size(4, traits(-1000), Config))
end)
