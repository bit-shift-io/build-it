-- Placing a building through the real input path: a number key picks a
-- design from the library, the pointer moves the ghost, R turns it, a left
-- click places it. The design library is a real file in love_mock's save
-- directory, read when the app starts.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local Inventory = require("src.game.components.inventory")
local Cost = require("src.game.builder.cost")
local DesignStore = require("src.app.design_store")

local TILE = Config.tileSize

local function brick(x, y, port)
	return { x = x, y = y, z = 0, width = 1, depth = 1, shape = "1x1", rotation = 0, material = "plank", paint = 1, port = port }
end

-- A 2x2 tile hall with an output port on its south edge, in tile (1, 1).
local HALL = {
	id = "d1",
	name = "Hall",
	versions = { { width = 2, depth = 2, bricks = { brick(2, 2), brick(6, 7, "output") } } },
}

-- 20x20 world, character at its centre (px 320, 320), HALL in the library.
local function launch()
	_G.love = LoveMock.new()
	assert(DesignStore.write(Config.designs.dir, HALL))
	local world = World.new(20, 20)
	local game = GameHarness.startSession(world)
	return game, Fake.FakeInput.new(), game.ctx.pools.characters[1], world
end

-- The screen pixel over world point (wx, wy) in tiles, camera on the
-- character at zoom 1 in the mock's 1280x720 window.
local function screenOf(c, wx, wy)
	return 640 + (wx * TILE - c.x), 360 + (wy * TILE - c.y)
end

-- Points at the middle of a 2x2 footprint whose north-west tile is (x, y).
local function pointAt(game, c, x, y)
	local sx, sy = screenOf(c, x + 1, y + 1)
	game:mousemoved(sx, sy, 0, 0)
	return sx, sy
end

test("picking a design and clicking places it, paying from the inventory", function()
	local game, _, c, world = launch()
	local planks = Inventory.count(c.inventory, "plank")

	Fake.tap(game, "1")
	local sx, sy = pointAt(game, c, 12, 9)
	Fake.click(game, 1, sx, sy)

	local buildings = game.ctx.pools.buildings
	assertEqual(1, #buildings)
	assertEqual("d1", buildings[1].design.id)
	assertEqual(1, buildings[1].version)
	assertEqual("N", buildings[1].facing)
	assertEqual(12, buildings[1].tileX)
	assertEqual(9, buildings[1].tileY)
	assertEqual(planks - Cost.of(HALL.versions[1], Config).plank, Inventory.count(c.inventory, "plank"))
	for y = 9, 10 do
		for x = 12, 13 do
			assertEqual(buildings[1], World.buildingAt(world, x, y))
		end
	end
	assertEqual(buildings[1].ports[1], World.portAt(world, 13, 11))
end)

test("the character cannot walk into a placed building", function()
	local game, input, c = launch()
	Fake.tap(game, "1")
	Fake.click(game, 1, pointAt(game, c, 12, 9)) -- footprint 12..13 x 9..10

	Fake.holdFor(game, input, "d", 1)

	assertEqual(12 * TILE - c.size / 2, c.x, "stops flush against the west wall")
end)

test("R turns the ghost to the next facing before placing", function()
	local game, _, c, world = launch()
	Fake.tap(game, "1")
	Fake.tap(game, "r")
	Fake.tap(game, "r")
	assertEqual("S", game.flow.world.placing.facing)
	Fake.tap(game, "r")
	Fake.tap(game, "r")
	Fake.tap(game, "r")
	Fake.click(game, 1, pointAt(game, c, 12, 9))

	local b = game.ctx.pools.buildings[1]
	assertEqual("E", b.facing)
	-- The south-edge output in tile (1, 1) turns to the west edge, tile (0, 1).
	assertEqual("W", b.ports[1].side)
	assertEqual(b.ports[1], World.portAt(world, 11, 10))
end)

local WorldScreen = require("src.app.screens.world")

test("an invalid placement is refused, says why and costs nothing", function()
	local game, _, c, world = launch()
	World.setTerrain(world, 13, 10, "water")
	local planks = Inventory.count(c.inventory, "plank")
	Fake.tap(game, "1")
	local sx, sy = pointAt(game, c, 12, 9)

	local screen = game.flow.world
	assertFalse(WorldScreen.ghost(screen).ok, "the ghost shows invalid")
	assertEqual("Can't place: it would stand on water", WorldScreen.status(screen))

	Fake.click(game, 1, sx, sy)
	assertEqual(0, #game.ctx.pools.buildings)
	assertEqual(planks, Inventory.count(c.inventory, "plank"))
	assertEqual("Can't place: it would stand on water", screen.message)

	c.inventory.counts.plank = 0
	sx, sy = pointAt(game, c, 12, 6)
	assertEqual("Can't place: not enough materials", WorldScreen.status(screen))
	Fake.click(game, 1, sx, sy)
	assertEqual(0, #game.ctx.pools.buildings)
end)

test("Esc or a right click leaves placement mode, and clicks harvest again", function()
	local game, _, c, world = launch()
	World.addNode(world, { id = 1, kind = "tree", tileX = 10, tileY = 9, variant = 1, stage = 1, amount = Config.nodes.tree.amount })
	Fake.tap(game, "1")
	Fake.tap(game, "escape")
	assertEqual(nil, game.flow.world.placing)
	assertEqual("world", game.flow.screen)

	Fake.tap(game, "1")
	local sx, sy = pointAt(game, c, 12, 9)
	Fake.click(game, 2, sx, sy)
	assertEqual(nil, game.flow.world.placing)
	Fake.click(game, 1, sx, sy)
	assertEqual(0, #game.ctx.pools.buildings)

	-- Holding a click on the adjacent tree harvests it.
	local tx, ty = screenOf(c, 10.5, 9.5)
	game:mousemoved(tx, ty, 0, 0)
	game:mousepressed(tx, ty, 1)
	Fake.runUntil(game, function()
		return Inventory.count(c.inventory, "log") > 0
	end, 120)
	game:mousereleased(tx, ty, 1)
end)

test("a click while placing never harvests", function()
	local game, _, c, world = launch()
	World.addNode(world, { id = 1, kind = "tree", tileX = 10, tileY = 9, variant = 1, stage = 1, amount = Config.nodes.tree.amount })
	Fake.tap(game, "1")
	local tx, ty = screenOf(c, 10.5, 9.5)
	game:mousemoved(tx, ty, 0, 0)
	game:mousepressed(tx, ty, 1)
	Fake.FakeInput.new() -- no keys held
	for _ = 1, 60 do
		game:update(1 / 60)
	end
	game:mousereleased(tx, ty, 1)
	assertEqual(0, Inventory.count(c.inventory, "log"))
end)
