-- HUD line builders: zero-count items are hidden.
local Inventory = require("src.game.components.inventory")
local Hud = require("src.app.render.hud")

test("hud inventory lines list only held items in order", function()
	local inv = Inventory.new()
	Inventory.add(inv, "plank", 2)
	Inventory.add(inv, "log", 5)
	local lines = Hud.inventoryLines(inv)
	assertEqual(2, #lines)
	assertEqual("log: 5", lines[1])
	assertEqual("plank: 2", lines[2])
end)

test("hud inventory lines are empty for an empty inventory", function()
	assertEqual(0, #Hud.inventoryLines(Inventory.new()))
end)

test("hud storage lines hide zero items but keep the header", function()
	local lines = Hud.storageLines({ stone = 3, log = 0 }, nil, 40)
	assertEqual(2, #lines)
	assertEqual("Storage 40%", lines[1])
	assertEqual("stone: 3", lines[2])
end)

test("hud storage lines keep a reserved-only item", function()
	local lines = Hud.storageLines({}, { log = 4 }, nil)
	assertEqual("Storage", lines[1])
	assertEqual("log: 0 (4 reserved)", lines[2])
end)

local Storage = require("src.game.components.storage")

local function port(kind, items)
	local p = { kind = kind, buffer = Storage.new(10), building = { functionBricks = { { depot = true } } } }
	for _ = 1, items or 0 do
		Storage.add(p.buffer, "log")
	end
	return p
end

test("hud port hint for output ports", function()
	local inv = Inventory.new()
	assertEqual("Output port: empty", Hud.portHint(port("output"), inv))
	assertEqual("E: collect 3 items", Hud.portHint(port("output", 3), inv))
end)

test("hud port hint for input ports follows what the inventory can deliver", function()
	local inv = Inventory.new()
	assertEqual("Input port: nothing accepted", Hud.portHint(port("input"), inv))
	Inventory.add(inv, "log", 1)
	assertEqual("E: deliver", Hud.portHint(port("input"), inv))
	local picky = port("input")
	picky.building = { functionBricks = {} }
	assertEqual("Input port: nothing accepted", Hud.portHint(picky, inv))
end)
