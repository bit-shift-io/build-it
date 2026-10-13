local Inventory = require("src.game.components.inventory")

test("a new inventory holds the stockpile and no logs", function()
	local inv = Inventory.new({ plank = 50, stone = 20 })
	assertEqual(50, Inventory.count(inv, "plank"))
	assertEqual(20, Inventory.count(inv, "stone"))
	assertEqual(0, Inventory.count(inv, "log"))
end)

test("add raises the count and does not touch the stockpile table", function()
	local stock = { plank = 1 }
	local inv = Inventory.new(stock)
	Inventory.add(inv, "log", 2)
	Inventory.add(inv, "plank")
	assertEqual(2, Inventory.count(inv, "log"))
	assertEqual(2, Inventory.count(inv, "plank"))
	assertEqual(1, stock.plank)
end)
