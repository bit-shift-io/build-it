-- Hand harvesting through the real input path: E (or a held click) works on
-- an adjacent node, logs and stone land in the inventory, trees step down to
-- their last stage and vanish, freeing the tile.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local Inventory = require("src.game.components.inventory")
local FrameStepper = require("tests.support.frame_stepper")

local TILE = Config.tileSize

-- 10x10 world, character at its centre (tile 5,5 corner, px 160,160); a
-- node of `kind` on tile (7, 5), two tiles east of the character's tile.
local function startWith(kind)
	_G.love = LoveMock.new()
	local world = World.new(10, 10)
	World.addNode(world, { id = 1, kind = kind, tileX = 7, tileY = 5, variant = 1, stage = 1, amount = Config.nodes[kind].amount })
	local game = GameHarness.startSession(world)
	return game, Fake.FakeInput.new(), game.ctx.pools.characters[1], world
end

local function walkToNode(game, input)
	Fake.holdFor(game, input, "d", 2) -- stops flush against the node
end

local function cycles(n)
	return n * Config.harvest.handCycle + 0.05
end

test("a new game starts with the configured stockpile", function()
	local _, _, c = startWith("tree")
	assertEqual(Config.stockpile.plank, Inventory.count(c.inventory, "plank"))
	assertEqual(Config.stockpile.stone, Inventory.count(c.inventory, "stone"))
	assertEqual(0, Inventory.count(c.inventory, "log"))
end)

test("holding E beside a tree yields logs, steps it down and clears its tile", function()
	local game, input, c, world = startWith("tree")
	walkToNode(game, input)
	local node = World.nodeAt(world, 7, 5)

	Fake.holdFor(game, input, "e", cycles(3))
	assertEqual(3, Inventory.count(c.inventory, "log"))
	assertEqual(7, node.amount)
	assertEqual(1, node.stage)

	Fake.holdFor(game, input, "e", cycles(Config.nodes.tree.amount))
	assertEqual(Config.nodes.tree.amount, Inventory.count(c.inventory, "log"))
	assertTrue(World.nodeAt(world, 7, 5) == nil, "tile cleared")
	assertFalse(World.isBlocked(world, 7, 5))
end)

test("the character walks through the tile of a felled tree", function()
	local game, input, c = startWith("tree")
	walkToNode(game, input)
	Fake.holdFor(game, input, "e", cycles(Config.nodes.tree.amount))

	Fake.holdFor(game, input, "d", 1)

	assertTrue(c.x > 8 * TILE, string.format("walked past tile 7, x = %.1f", c.x))
end)

test("E out of reach harvests nothing", function()
	local game, input, c = startWith("tree")
	Fake.holdFor(game, input, "e", 2)
	assertEqual(0, Inventory.count(c.inventory, "log"))
end)

test("harvesting a rock adds stone and the rock disappears when empty", function()
	local game, input, c, world = startWith("rock")
	walkToNode(game, input)

	Fake.holdFor(game, input, "e", cycles(Config.nodes.rock.amount))

	assertEqual(Config.stockpile.stone + Config.nodes.rock.amount, Inventory.count(c.inventory, "stone"))
	assertTrue(World.nodeAt(world, 7, 5) == nil, "tile cleared")
	assertEqual(0, #world.nodes)
	assertEqual(0, #game.ctx.pools.nodes)
	assertFalse(World.isBlocked(world, 7, 5))
end)

test("holding a click on an adjacent node harvests it", function()
	local game, input, c, world = startWith("tree")
	walkToNode(game, input)
	-- Camera follows the character at screen centre (1280x720, zoom 1).
	local sx = 640 + (7.5 * TILE - c.x)
	local sy = 360 + (5.5 * TILE - c.y)

	game:mousemoved(sx, sy, 0, 0)
	game:mousepressed(sx, sy, 1)
	FrameStepper.step(game, FrameStepper.secondsToFrames(cycles(2)))
	game:mousereleased(sx, sy, 1)
	FrameStepper.step(game, 30)

	assertEqual(2, Inventory.count(c.inventory, "log"))
	assertEqual(Config.nodes.tree.amount - 2, World.nodeAt(world, 7, 5).amount)
end)
