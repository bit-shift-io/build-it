local Harvestable = require("src.game.components.harvestable")
local Inventory = require("src.game.components.inventory")
local Config = require("src.game.config")

local function tree()
	return { kind = "tree", amount = Config.nodes.tree.amount, stage = 1 }
end
local function rock()
	return { kind = "rock", amount = Config.nodes.rock.amount, stage = 1 }
end
local function worker()
	return { progress = 0 }
end

local CYCLE = Config.harvest.handCycle

test("a cycle takes the configured time before yielding an item", function()
	local inv, w, n = Inventory.new(), worker(), tree()
	Harvestable.work(w, n, CYCLE * 0.9, inv, Config)
	assertEqual(0, Inventory.count(inv, "log"))
	Harvestable.work(w, n, CYCLE * 0.2, inv, Config)
	assertEqual(1, Inventory.count(inv, "log"))
	assertEqual(Config.nodes.tree.amount - 1, n.amount)
end)

test("a rock yields stone", function()
	local inv = Inventory.new()
	Harvestable.work(worker(), rock(), CYCLE, inv, Config)
	assertEqual(1, Inventory.count(inv, "stone"))
end)

test("a tree steps through all its stages and is dead when depleted", function()
	local inv, w, n = Inventory.new(), worker(), tree()
	assertEqual(1, n.stage)
	local seen = {}
	for _ = 1, Config.nodes.tree.amount do
		assertFalse(n.dead)
		Harvestable.work(w, n, CYCLE, inv, Config)
		seen[n.stage] = true
	end
	assertTrue(seen[2], "half-felled stage visited")
	assertTrue(seen[3], "last stage visited")
	assertEqual(0, n.amount)
	assertTrue(n.dead)
	assertEqual(Config.nodes.tree.amount, Inventory.count(inv, "log"))
end)

test("a depleted node yields nothing more", function()
	local inv, w, n = Inventory.new(), worker(), tree()
	n.amount = 0
	Harvestable.work(w, n, CYCLE * 5, inv, Config)
	assertEqual(0, Inventory.count(inv, "log"))
	assertFalse(Harvestable.canHarvest(n))
end)

test("a rock passes through its stages and is marked dead when empty", function()
	local inv, w, n = Inventory.new(), worker(), rock()
	local seen = {}
	for _ = 1, Config.nodes.rock.amount do
		assertFalse(n.dead)
		Harvestable.work(w, n, CYCLE, inv, Config)
		seen[n.stage] = true
	end
	assertTrue(seen[2] and seen[3], "half and last chunk stages visited")
	assertTrue(n.dead)
	assertEqual(Config.nodes.rock.amount, Inventory.count(inv, "stone"))
end)
