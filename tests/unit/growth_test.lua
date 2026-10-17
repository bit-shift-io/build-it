-- Saplings grow through stages into full trees over config.nodes.tree.growTime.
local Session = require("src.game.session")
local World = require("src.game.world")
local Config = require("src.game.config")
local Harvestable = require("src.game.components.harvestable")
local NodeSystem = require("src.game.systems.node_system")

local STEP = 1 / 60

local function setup()
	local config = setmetatable({ nodes = { tree = { amount = 10, item = "log", stageAt = { 0.6, 0.3 }, growTime = 10 }, rock = Config.nodes.rock } }, { __index = Config })
	local ctx = Session.new(World.new(10, 10), config, 1)
	local n = NodeSystem.plant(ctx, "tree", 2, 2)
	return ctx, n
end

local function run(ctx, seconds)
	for _ = 1, math.floor(seconds / STEP + 0.5) do
		Session.advance(ctx, STEP)
	end
end

test("a planted sapling starts at the sapling stage and cannot be harvested", function()
	local ctx, n = setup()
	assertEqual(4, n.stage)
	assertFalse(Harvestable.canHarvest(n))
	assertEqual(n, World.nodeAt(ctx.world, 2, 2))
end)

test("a sapling steps to the young stage, then becomes a full harvestable tree", function()
	local ctx, n = setup()
	run(ctx, 4)
	assertEqual(4, n.stage)
	run(ctx, 2)
	assertEqual(5, n.stage)
	assertFalse(Harvestable.canHarvest(n))
	run(ctx, 4.1)
	assertEqual(1, n.stage)
	assertEqual(nil, n.growing)
	assertTrue(Harvestable.canHarvest(n))
end)

test("a sapling is not free for a saw to reserve until grown", function()
	local ctx, n = setup()
	assertFalse(NodeSystem.isFree(n))
	run(ctx, 11)
	assertTrue(NodeSystem.isFree(n))
end)

test("planted node ids never repeat after a removal", function()
	local ctx, a = setup()
	local b = NodeSystem.plant(ctx, "tree", 3, 3)
	a.dead = true
	run(ctx, STEP)
	local c = NodeSystem.plant(ctx, "tree", 4, 4)
	assertTrue(c.id ~= b.id)
end)

test("a picked-clean bush refills in the configured time and is never removed", function()
	local ctx = Session.new(World.new(10, 10), Config, 1)
	local n = World.addNode(ctx.world, { id = 1, kind = "bush", tileX = 2, tileY = 2, variant = 1, stage = 1, amount = Config.nodes.bush.amount })
	while Harvestable.canHarvest(n) do
		Harvestable.take(n, Config)
	end
	assertEqual(3, n.stage)
	run(ctx, Config.nodes.bush.refillTime - 1)
	assertEqual(n, World.nodeAt(ctx.world, 2, 2))
	assertFalse(Harvestable.canHarvest(n))
	assertEqual(3, n.stage)
	run(ctx, 2)
	assertEqual(n, World.nodeAt(ctx.world, 2, 2))
	assertTrue(Harvestable.canHarvest(n))
	assertEqual(1, n.stage)
	assertEqual(Config.nodes.bush.amount, n.amount)
	assertEqual(nil, n.refilling)
end)
