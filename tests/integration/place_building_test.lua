-- Placing a building through the real input path: a number key opens the
-- picker on the library's placeable designs, the pointer moves the ghost,
-- R turns it, a left click places its blueprint. The designs are real Lua
-- files in love_mock's save directory, read when the picker opens.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local Inventory = require("src.game.components.inventory")
local StorageFacility = require("src.game.components.storage_facility")
local DesignStore = require("src.app.design_store")
local Session = require("src.game.session")
local Designs = require("tests.support.designs")

local TILE = Config.tileSize

-- A 2x2 tile hall: a bed, and an output port on its south edge in tile
-- (1, 1).
local HALL = Designs.floor(2, 2, Designs.ability("bed", 0.625, 0.625), Designs.port("output", 1.625, 2))

local function write(name, text)
	assert(DesignStore.write(Config.designs, "designs", name, text))
end

-- 20x20 world, character at its centre (px 320, 320), HALL in the library
-- as "hall", a storage facility holding the stockpile in the south-east
-- corner tile (ctx.pools.buildings[1]).
local function launch()
	_G.love = LoveMock.new()
	write("hall", HALL)
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

	Fake.pickDesign(game, "hall")
	local sx, sy = pointAt(game, c, 12, 9)
	Fake.click(game, 1, sx, sy)

	assertEqual(1, #game.ctx.pools.buildings, "no building yet")
	local site = game.ctx.pools.sites[1]
	assert(site, "a site")
	assertEqual("hall", site.design)
	assertEqual(Designs.blueprint(HALL).hash, site.blueprint.hash, "its blueprint compiled from the file")
	assertEqual("N", site.facing)
	assertEqual(12, site.tileX)
	assertEqual(9, site.tileY)
	local cost = site.blueprint.cost.plank
	assertEqual(planks - cost, stored(game, "plank"), "the totals drop: the cost is reserved")
	assertEqual(cost, StorageFacility.claimed(game.ctx).plank)
	assertEqual(0, Inventory.count(c.inventory, "plank"), "the inventory pays nothing")
	for y = 9, 10 do
		for x = 12, 13 do
			assertEqual(site, World.buildingAt(world, x, y))
		end
	end
	assertEqual(nil, World.portAt(world, 13, 11), "no port until built")
end)

-- A woodcutter as a player writes it by hand: a 2 x 1 tile floor, a saw
-- prefab on its north row and an output port prefab on its south edge
-- under tile (1, 0).
local WOODCUTTER = [[
local W, D = 2, 1
return group{ id = "root", name = "Woodcutter",
	box{ id = "floor", name = "Floor", size = { W, D, 0.125 } },
	prefab("saw", { id = "saw", transform = { move = { 0, 0, 0 } } }),
	prefab("output_port", { id = "out", transform = { move = { 1, D - 0.25, 0 } } }),
}
]]

test("villagers haul a placed woodcutter's cost from storage and build it, then it produces", function()
	_G.love = LoveMock.new()
	write("woodcutter", WOODCUTTER)
	local world = World.new(20, 20)
	for y = 4, 6 do
		World.addNode(world, { id = y, kind = "tree", tileX = 11, tileY = y, variant = 1, stage = 1, amount = Config.nodes.tree.amount })
	end
	local game = GameHarness.startSession(world, { storage = Config.stockpile })
	local c = game.ctx.pools.characters[1]
	local facility = game.ctx.pools.buildings[1]
	local held = stored(game, "plank")
	for i = 1, 2 do
		table.insert(game.ctx.pools.villagers, Session.newVillager(i, (14 + i + 0.5) * TILE, 16.5 * TILE, Config))
	end

	-- Footprint (12..13, 7); the ghost centres on the pointer.
	Fake.pickDesign(game, "wood")
	Fake.click(game, 1, 640 + (13 * TILE - c.x), 360 + (7.5 * TILE - c.y))
	local site = game.ctx.pools.sites[1]
	assert(site, "a site")
	local cost = site.blueprint.cost
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
	assertEqual(held - cost.plank, stored(game, "plank"), "the cost left the facility")
	assertEqual(nil, StorageFacility.claimed(game.ctx).plank, "nothing reserved any more")

	Fake.runUntil(game, function()
		return (facility.storage.counts.log or 0) > 0
	end, 60 * 120)
	assertEqual(0, Inventory.count(c.inventory, "log"), "the player did nothing")

	-- Saved with F5 and continued after a relaunch over the same files.
	game:keypressed("f5")
	_G.love = LoveMock.new({ saveDir = love.filesystem.getSaveDirectory() })
	local again = GameHarness.launch()
	again:keypressed("return")
	assertEqual("world", again.flow.screen)
	local lb = again.ctx.pools.buildings[2]
	assertEqual("woodcutter", lb.design)
	assertEqual(b.blueprint.hash, lb.blueprint.hash)
	assertEqual("saw", lb.functionBricks[1].ability)
	assertEqual(lb.ports[1], World.portAt(again.ctx.world, 13, 8))
end)

test("the character cannot walk into a placed building", function()
	local game, input, c = launch()
	Fake.pickDesign(game, "hall")
	Fake.click(game, 1, pointAt(game, c, 12, 9)) -- footprint 12..13 x 9..10

	Fake.holdFor(game, input, "d", 1)

	assertEqual(12 * TILE - c.size / 2, c.x, "stops flush against the west wall")
end)

test("R turns the ghost to the next facing before placing", function()
	local game, _, c, world = launch()
	Fake.pickDesign(game, "hall")
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
	Fake.pickDesign(game, "hall")
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
	Fake.pickDesign(game, "hall")
	Fake.tap(game, "escape")
	assertEqual(nil, game.flow.world.placing)
	assertEqual("world", game.flow.screen)

	Fake.pickDesign(game, "hall")
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
	Fake.pickDesign(game, "hall")
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

local SaveCodec = require("src.game.save.codec")

-- A design named `name`: HALL, so each has a bed and can be placed.
local function launchWith(names)
	_G.love = LoveMock.new()
	for _, name in ipairs(names) do
		write(name, HALL)
	end
	local game = GameHarness.startSession(World.new(20, 20), { storage = Config.stockpile })
	return game, game.ctx.pools.characters[1]
end

-- The sorted, comma-joined names of the built-in designs and `extra`.
local function withBuiltins(...)
	local names = { ... }
	for _, name in ipairs(require("src.game.designs.builtins").DESIGNS) do
		names[#names + 1] = name
	end
	table.sort(names)
	return table.concat(names, ",")
end

test("key 1 then Enter places the first design by name, built-ins included", function()
	local game = launchWith({ "b", "a", "c" })
	Fake.tap(game, "1")
	assertEqual(withBuiltins("a", "b", "c"), (function()
		local names = {}
		for i, d in ipairs(game.flow.world.picker.designs) do
			names[i] = d.name
		end
		return table.concat(names, ",")
	end)())
	Fake.tap(game, "return")
	assertEqual("a", game.flow.world.placing.design)
end)

test("a design file written while the game runs shows in the picker; one with no function role never does", function()
	local game = launchWith({})
	write("shed", "return group{ box{ size = { 1, 1, 1 } } }")
	write("broken", "return group{")
	write("mill", HALL)
	Fake.tap(game, "1")
	local names = {}
	for _, d in ipairs(game.flow.world.picker.designs) do
		names[#names + 1] = d.name
	end
	assertEqual(withBuiltins("mill"), table.concat(names, ","))
end)

test("a building whose design file is deleted survives save and load", function()
	local game, c = launchWith({ "a" })
	Fake.pickDesign(game, "a")
	local sx, sy = pointAt(game, c, 12, 9)
	Fake.click(game, 1, sx, sy)
	GameHarness.completeSites(game)
	assertTrue(love.filesystem.remove(Config.designs.dir .. "/a.lua"), "fixture: the file is gone")
	local b = game.ctx.pools.buildings[2]
	local text = SaveCodec.encode(game.ctx)
	local ctx = assert(SaveCodec.decode(text, Config))
	assertEqual(2, #ctx.pools.buildings)
	assertEqual("a", ctx.pools.buildings[2].design)
	assertEqual(b.blueprint.hash, ctx.pools.buildings[2].blueprint.hash)
	assertEqual(text, SaveCodec.encode(ctx))
end)

local PickerRender = require("src.app.render.picker")
local Picker = require("src.app.picker")

local function rowCentre(i)
	local row = PickerRender.row(1280, 720, i)
	return row.x + row.w / 2, row.y + row.h / 2
end

test("right-click, Build, type a name, click the row: placing that design", function()
	local game = launchWith({ "hall", "foundry", "hut" })
	local screen = game.flow.world
	Fake.click(game, 2, 300, 200)
	assertTrue(screen.menu ~= nil, "menu opened")
	Fake.click(game, 1, 310, 210)
	assertEqual(nil, screen.menu)
	assertTrue(screen.picker ~= nil, "picker opened")
	Fake.typeText(game, "FOUN")
	assertEqual(1, #Picker.matches(screen.picker))
	Fake.click(game, 1, rowCentre(1))
	assertEqual(nil, screen.picker)
	assertEqual("foundry", screen.placing.design)
end)

test("a right-click outside the menu closes it", function()
	local game = launchWith({ "hall" })
	local screen = game.flow.world
	Fake.click(game, 2, 300, 200)
	Fake.click(game, 1, 900, 600)
	assertEqual(nil, screen.menu)
	assertEqual(nil, screen.picker)
end)

test("key 1 opens the picker without typing 1, and Esc or right-click closes it", function()
	local game = launchWith({ "hall" })
	local screen = game.flow.world
	game:keypressed("1")
	game:textinput("1")
	Fake.typeText(game, "1")
	assertEqual("1", screen.picker.query, "only the second 1 is typed")
	Fake.tap(game, "backspace")
	assertEqual("", screen.picker.query)
	Fake.tap(game, "escape")
	assertEqual(nil, screen.picker)
	Fake.tap(game, "1")
	Fake.click(game, 2, 100, 100)
	assertEqual(nil, screen.picker)
	assertEqual(nil, screen.menu)
end)

test("typing e, w, a, s, d in the search moves no one and harvests nothing", function()
	local game, c = launchWith({ "hall" })
	World.addNode(game.ctx.world, { id = 1, kind = "tree", tileX = 10, tileY = 10, variant = 1, stage = 1, amount = Config.nodes.tree.amount })
	local screen = game.flow.world
	local x, y = c.x, c.y
	Fake.tap(game, "1")
	local input = Fake.FakeInput.new()
	for _, key in ipairs({ "e", "w", "a", "s", "d" }) do
		input:press(key)
		game:keypressed(key)
		game:textinput(key)
		Fake.holdFor(game, input, key, 0.5)
	end
	assertEqual("ewasd", screen.picker.query)
	assertEqual(x, c.x)
	assertEqual(y, c.y)
	assertEqual(Config.nodes.tree.amount, game.ctx.pools.nodes[1].amount)
	assertEqual("world", game.flow.screen, "b is typed, not the builder")
end)

test("the wheel scrolls the picker, not the camera, and reaches the 15th design", function()
	local names = {}
	for i = 1, 15 do
		names[i] = string.format("design_%02d", i)
	end
	local game = launchWith(names)
	local screen = game.flow.world
	local zoom = screen.camera.zoom
	Fake.tap(game, "1")
	Fake.typeText(game, "design")
	game:wheelmoved(0, -20)
	assertEqual(zoom, screen.camera.zoom)
	assertEqual(3, screen.picker.scroll)
	Fake.click(game, 1, rowCentre(Picker.ROWS))
	assertEqual("design_15", screen.placing.design)
end)

test("the hover card hides while the menu or picker is open", function()
	local game = launchWith({ "hall" })
	local screen = game.flow.world
	local c = game.ctx.pools.characters[1]
	game:mousemoved(640, 360, 0, 0)
	Fake.click(game, 2, 640, 360)
	assertEqual(nil, WorldScreen.hovered(screen))
end)
