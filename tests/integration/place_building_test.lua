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
local StorageFacility = require("src.game.components.storage_facility")
local Cost = require("src.game.builder.cost")
local DesignStore = require("src.app.design_store")
local Session = require("src.game.session")

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

-- 20x20 world, character at its centre (px 320, 320), HALL in the library,
-- a storage facility holding the stockpile in the south-east corner tile
-- (ctx.pools.buildings[1]).
local function launch()
	_G.love = LoveMock.new()
	assert(DesignStore.write(Config.designs.dir, HALL))
	local world = World.new(20, 20)
	local game = GameHarness.startSession(world, { storage = Config.stockpile })
	return game, Fake.FakeInput.new(), game.ctx.pools.characters[1], world
end

local function stored(game, item)
	return StorageFacility.totals(game.ctx)[item] or 0
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

test("picking a design and clicking places a construction site, its cost reserved in storage", function()
	local game, _, c, world = launch()
	local planks = stored(game, "plank")
	local facility = game.ctx.pools.buildings[1]
	local held = facility.storage.counts.plank

	Fake.tap(game, "1")
	local sx, sy = pointAt(game, c, 12, 9)
	Fake.click(game, 1, sx, sy)

	assertEqual(1, #game.ctx.pools.buildings, "no building yet")
	local site = game.ctx.pools.sites[1]
	assert(site, "a site")
	assertEqual("d1", site.design.id)
	assertEqual(1, site.version)
	assertEqual("N", site.facing)
	assertEqual(12, site.tileX)
	assertEqual(9, site.tileY)
	local cost = Cost.of(HALL.versions[1], Config).plank
	assertEqual(planks - cost, stored(game, "plank"), "the totals drop: the cost is reserved")
	assertEqual(cost, StorageFacility.claimed(game.ctx).plank)
	assertEqual(held, facility.storage.counts.plank, "it stays in storage until hauled")
	assertEqual(0, Inventory.count(c.inventory, "plank"), "the inventory pays nothing")
	for y = 9, 10 do
		for x = 12, 13 do
			assertEqual(site, World.buildingAt(world, x, y))
		end
	end
	assertEqual(nil, World.portAt(world, 13, 11), "no port until built")
end)

-- Bricks as the builder saves them: a plank saw on the north row of a 2x1
-- tile baseplate and an output port on its south edge under tile (1, 0).
local WOODCUTTER = {
	id = "d1",
	name = "Woodcutter",
	versions = {
		{
			width = 2,
			depth = 1,
			bricks = {
				{ x = 0, y = 0, z = 0, width = 3, depth = 1, height = 3, shape = "saw", rotation = 0, material = "plank", paint = 1, ability = "saw" },
				{ x = 3, y = 3, z = 0, width = 2, depth = 1, height = 1, shape = "output", rotation = 0, material = "plank", paint = 2, port = "output" },
			},
		},
	},
}

test("villagers haul a placed woodcutter's cost from storage and build it, then it produces", function()
	_G.love = LoveMock.new()
	assert(DesignStore.write(Config.designs.dir, WOODCUTTER))
	local world = World.new(20, 20)
	for y = 4, 6 do
		World.addNode(world, { id = y, kind = "tree", tileX = 11, tileY = y, variant = 1, stage = 1, amount = Config.nodes.tree.amount })
	end
	local game = GameHarness.startSession(world, { storage = Config.stockpile })
	local c = game.ctx.pools.characters[1]
	local facility = game.ctx.pools.buildings[1]
	local held = facility.storage.counts.plank
	for i = 1, 2 do
		table.insert(game.ctx.pools.villagers, Session.newVillager(i, (14 + i + 0.5) * TILE, 16.5 * TILE, Config))
	end

	-- Footprint (12..13, 7); the ghost centres on the pointer.
	Fake.tap(game, "1")
	Fake.click(game, 1, 640 + (13 * TILE - c.x), 360 + (7.5 * TILE - c.y))
	assert(game.ctx.pools.sites[1], "a site")
	local hauled, built = false, false
	Fake.runUntil(game, function()
		for _, job in ipairs(game.ctx.pools.jobs) do
			hauled = hauled or (job.kind == "haul" and job.dest.building == game.ctx.pools.sites[1])
			built = built or job.kind == "build"
		end
		return #game.ctx.pools.sites == 0
	end, 60 * 120)
	assertTrue(hauled and built, "villagers hauled and built it")

	local b = game.ctx.pools.buildings[2]
	assert(b, "the site became a building")
	assertEqual(b, World.buildingAt(world, 12, 7))
	assertEqual(b.ports[1], World.portAt(world, 13, 8))
	local cost = Cost.of(WOODCUTTER.versions[1], Config).plank
	assertEqual(held - cost, facility.storage.counts.plank, "the cost left storage")
	assertEqual(nil, StorageFacility.claimed(game.ctx).plank, "nothing reserved any more")

	Fake.runUntil(game, function()
		return (facility.storage.counts.log or 0) > 0
	end, 60 * 120)
	assertEqual(0, Inventory.count(c.inventory, "log"), "the player did nothing")
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
	assertEqual("E", game.ctx.pools.sites[1].facing)
	GameHarness.completeSites(game)

	local b = game.ctx.pools.buildings[2]
	assertEqual("E", b.facing)
	-- The south-edge output in tile (1, 1) turns to the west edge, tile (0, 1).
	assertEqual("W", b.ports[1].side)
	assertEqual(b.ports[1], World.portAt(world, 11, 10))
end)

local WorldScreen = require("src.app.screens.world")

test("an invalid placement is refused, says why and costs nothing", function()
	local game, _, c, world = launch()
	World.setTerrain(world, 13, 10, "water")
	local planks = stored(game, "plank")
	Fake.tap(game, "1")
	local sx, sy = pointAt(game, c, 12, 9)

	local screen = game.flow.world
	assertFalse(WorldScreen.ghost(screen).ok, "the ghost shows invalid")
	assertEqual("Can't place: it would stand on water", WorldScreen.status(screen))

	Fake.click(game, 1, sx, sy)
	assertEqual(1, #game.ctx.pools.buildings, "only the storage facility")
	assertEqual(0, #game.ctx.pools.sites)
	assertEqual(planks, stored(game, "plank"))
	assertEqual("Can't place: it would stand on water", screen.message)

	game.ctx.pools.buildings[1].storage.counts.plank = 0
	c.inventory.counts.plank = 1000 -- the inventory never pays
	sx, sy = pointAt(game, c, 12, 6)
	assertEqual("Can't place: not enough materials", WorldScreen.status(screen))
	Fake.click(game, 1, sx, sy)
	assertEqual(1, #game.ctx.pools.buildings)
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
	assertEqual(1, #game.ctx.pools.buildings, "only the storage facility")

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
