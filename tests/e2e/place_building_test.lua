-- Placing buildings under real LÖVE 12: an asymmetric fixture design with
-- an input and an output port placed in all 4 facings, each with its port
-- tile markers, and the placement ghost valid and invalid. Captures land in
-- tests/screenshots/place_building_test/.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local Screen = require("src.app.screen")
local WorldScreen = require("src.app.screens.world")
local DesignStore = require("src.app.design_store")
local Placement = require("src.game.buildings.placement")

local TILE = Config.tileSize

local function configWithDesignDir(dir)
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.designs = { dir = dir, maxNameLength = Config.designs.maxNameLength }
	return config
end

local function clearDir(dir)
	for _, name in ipairs(love.filesystem.getDirectoryItems(dir)) do
		love.filesystem.remove(dir .. "/" .. name)
	end
end

local function brick(shape, x, y, z, width, depth, paint, port)
	return { shape = shape, rotation = 0, x = x, y = y, z = z, width = width, depth = depth, material = "plank", paint = paint, port = port }
end

-- A 3x2 tile works: a tan wall along the south, a red tower in the
-- north-east corner, a blue input port on the west edge (tile 0, 1) and an
-- orange output port on the north edge (tile 2, 0).
local function works()
	local bricks = {
		brick("1x1", 0, 5, 0, 1, 1, 8, "input"),
		brick("1x1", 9, 0, 0, 1, 1, 2, "output"),
	}
	for z = 0, 2 do
		for x = 0, 8, 4 do
			table.insert(bricks, brick("2x4", x, 6, z, 4, 2, 4))
		end
	end
	for z = 0, 5 do
		table.insert(bricks, brick("2x2", 10, 0, z, 2, 2, 1))
	end
	return { id = "d1", name = "Works", versions = { { width = 3, depth = 2, bricks = bricks } } }
end

local function screenOf(game, c, wx, wy)
	local w, h = Screen.dimensions()
	local zoom = game.camera.zoom
	return w / 2 + (wx * TILE - c.x) * zoom, h / 2 + (wy * TILE - c.y) * zoom
end

test("a design places in all 4 facings with its port tiles marked, and the ghost shows valid and invalid", function()
	local config = configWithDesignDir("e2e_place_designs")
	clearDir(config.designs.dir)
	assert(DesignStore.write(config.designs.dir, works()))

	local world = World.new(30, 20)
	for x = 2, 6 do
		World.setTerrain(world, x, 17, "water")
		World.setTerrain(world, x, 18, "water")
	end
	local game = GameHarness.startSession(world, { real = true, config = config })
	local c = game.ctx.pools.characters[1]
	local screen = game.flow.world
	c.inventory.counts.plank = 1000 -- 5 placements of 110 planks and more

	Fake.tap(game, "1")
	-- One building per facing in a row south of the character (the test
	-- house row stands north of it), footprints 3x2 or 2x3.
	local spots = { N = { 3, 12 }, E = { 9, 12 }, S = { 15, 12 }, W = { 21, 12 } }
	for _, facing in ipairs({ "N", "E", "S", "W" }) do
		assertEqual(facing, screen.placing.facing)
		local spot = spots[facing]
		local w, d = Placement.footprint(screen.placing.design.versions[1], facing)
		Fake.click(game, 1, screenOf(game, c, spot[1] + w / 2, spot[2] + d / 2))
		Fake.tap(game, "r")
	end

	local buildings = game.ctx.pools.buildings
	assertEqual(4, #buildings)
	for i, facing in ipairs({ "N", "E", "S", "W" }) do
		local b = buildings[i]
		assertEqual(facing, b.facing)
		assertEqual(spots[facing][1], b.tileX)
		assertEqual(spots[facing][2], b.tileY)
		assertEqual(2, #b.ports)
		for _, port in ipairs(b.ports) do
			assertEqual(port, World.portAt(world, port.x, port.y))
		end
	end
	Fake.tap(game, "escape")
	game:mousemoved(5, 5, 0, 0)
	Capture.capture("placed_all_facings")

	Fake.tap(game, "1")
	game:mousemoved(screenOf(game, c, 12.5, 18))
	assertTrue(WorldScreen.ghost(screen).ok, "expected a valid ghost on grass")
	Capture.capture("ghost_valid")

	game:mousemoved(screenOf(game, c, 4.5, 18))
	assertFalse(WorldScreen.ghost(screen).ok, "expected an invalid ghost on water")
	assertEqual("Can't place: it would stand on water", WorldScreen.status(screen))
	Capture.capture("ghost_invalid")
end)
