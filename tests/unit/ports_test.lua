-- Port buffers (src/game/components/ports.lua): sized by the capacity
-- trait; products go to storage, then output buffers; the player empties
-- an output buffer into their inventory.
local Ports = require("src.game.components.ports")
local Storage = require("src.game.components.storage")
local Inventory = require("src.game.components.inventory")
local Config = require("src.game.config")

local function traits(capacity)
	return { productivity = 0, capacity = capacity, reach = 0, health = 0 }
end

local function building(storage, ...)
	local ports = {}
	for _, kind in ipairs({ ... }) do
		table.insert(ports, { kind = kind })
	end
	Ports.setup(ports, traits(0), Config)
	return { storage = Storage.new(storage), ports = ports }
end

test("capacity grows every port buffer", function()
	local plain, roomy = { {}, {} }, { {} }
	Ports.setup(plain, traits(0), Config)
	Ports.setup(roomy, traits(20), Config)
	assertEqual(Config.production.bufferSize, plain[1].buffer.capacity)
	assertEqual(Config.production.bufferSize, plain[2].buffer.capacity)
	assertTrue(roomy[1].buffer.capacity > Config.production.bufferSize)
end)

test("products go to storage first, then output buffers, never inputs", function()
	local b = building(1, "input", "output")
	Ports.push(b, "log")
	assertEqual(1, b.storage.counts.log)
	for _ = 1, Config.production.bufferSize do
		Ports.push(b, "log")
	end
	assertEqual(Config.production.bufferSize, b.ports[2].buffer.counts.log)
	assertEqual(nil, b.ports[1].buffer.counts.log, "inputs take nothing")
	assertFalse(Ports.hasRoom(b))
end)

test("room reserved by a job on its way still counts as room until the items land", function()
	local b = building(0, "output")
	Storage.reserveRoom(b.ports[1].buffer, Config.production.bufferSize)
	assertTrue(Ports.hasRoom(b), "nothing stored yet")
end)

test("flushing moves stored items into output buffers with room", function()
	local b = building(10, "output")
	for _ = 1, 6 do
		Ports.push(b, "stone")
	end
	Ports.flush(b)
	assertEqual(Config.production.bufferSize, b.ports[1].buffer.counts.stone)
	assertEqual(6 - Config.production.bufferSize, b.storage.counts.stone)
end)

test("collecting empties an output buffer into the inventory", function()
	local b = building(0, "output")
	Ports.push(b, "log")
	Ports.push(b, "stone")
	Ports.push(b, "log")
	local inv = Inventory.new({ log = 1 })
	Ports.collect(b.ports[1], inv)
	assertEqual(3, Inventory.count(inv, "log"))
	assertEqual(1, Inventory.count(inv, "stone"))
	assertEqual(0, Storage.total(b.ports[1].buffer))
end)
