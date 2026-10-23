-- Placing buildings under real LÖVE 12: an asymmetric fixture design with
-- an input and an output port placed in all 4 facings as construction
-- sites, built by villagers into buildings with their port tile markers,
-- and the placement ghost valid and invalid. Captures land in
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
local Session = require("src.game.session")

local TILE = Config.tileSize

local function configWithDesignDirs(dir, prefabDir)
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.designs = { dir = dir, prefabDir = prefabDir }
	return config
end

local function clearDir(dir)
	for _, name in ipairs(love.filesystem.getDirectoryItems(dir)) do
		love.filesystem.remove(dir .. "/" .. name)
	end
end

-- A 3x2 tile works, as a player writes it by hand: a wall along the
-- south, a tower in the north-east corner, a saw (so the picker offers
-- it), an input port on the west edge (tile 0, 1) and an output port on
-- the north edge (tile 2, 0).
local WORKS = [[
return group{ id = "root", name = "Works",
	box{ id = "floor", name = "Floor", size = { 3, 2, 0.125 } },
	box{ id = "wall", name = "Wall", size = { 3, 0.5, 0.75 }, transform = { move = { 0, 1.5, 0 } } },
	box{ id = "tower", name = "Tower", size = { 0.5, 0.5, 1.5 }, transform = { move = { 2.5, 0, 0 } } },
	prefab("saw", { id = "saw", transform = { move = { 1, 0.5, 0.125 } } }),
	role{ id = "in", port = "input", transform = { move = { 0, 1.375, 0 } } },
	role{ id = "out", port = "output", transform = { move = { 2.375, 0, 0 } } },
}
]]

local function screenOf(game, c, wx, wy)
	local w, h = Screen.dimensions()
	local zoom = game.camera.zoom
	return w / 2 + (wx * TILE - c.x) * zoom, h / 2 + (wy * TILE - c.y) * zoom
end

test("a design places in all 4 facings with its port tiles marked, and the ghost shows valid and invalid", function()
	local config = configWithDesignDirs("e2e_place_designs", "e2e_place_prefabs")
	clearDir(config.designs.dir)
	clearDir(config.designs.prefabDir)
	assert(DesignStore.write(config.designs, "designs", "works", WORKS))

	local world = World.new(30, 20)
	for x = 2, 6 do
		World.setTerrain(world, x, 17, "water")
		World.setTerrain(world, x, 18, "water")
	end
	-- Storage for 5 placements and more.
	local game = GameHarness.startSession(world, { real = true, config = config, storage = { plank = 1000, stone = 1000 } })
	local c = game.ctx.pools.characters[1]
	local screen = game.flow.world

	Fake.pickDesign(game, "works")
	-- One building per facing in a row south of the character,
	-- footprints 3x2 or 2x3.
	local spots = { N = { 3, 12 }, E = { 9, 12 }, S = { 15, 12 }, W = { 21, 12 } }
	for _, facing in ipairs({ "N", "E", "S", "W" }) do
		assertEqual(facing, screen.placing.facing)
		local spot = spots[facing]
		local w, d = Placement.footprint(screen.placing.blueprint, facing)
		Fake.click(game, 1, screenOf(game, c, spot[1] + w / 2, spot[2] + d / 2))
		Fake.tap(game, "r")
	end

	-- Sites first: translucent, their cost reserved, nothing delivered.
	assertEqual(4, #game.ctx.pools.sites, "one site per facing")
	assertEqual(1, #game.ctx.pools.buildings, "only the storage facility")
	Fake.tap(game, "escape")
	game:mousemoved(5, 5, 0, 0)
	Capture.capture("sites_all_facings")

	-- Villagers by the storage facility haul the cost and build them.
	for i = 1, 20 do
		local x, y = 18 + (i - 1) % 10, 15 + math.floor((i - 1) / 10)
		table.insert(game.ctx.pools.villagers, Session.newVillager(i, (x + 0.5) * TILE, (y + 0.5) * TILE, config))
	end
	Fake.runUntil(game, function()
		local site = game.ctx.pools.sites[1]
		return site and (site.delivered.counts.plank or 0) > 0
	end, 60 * 60)
	Capture.capture("sites_part_delivered")
	Fake.runUntil(game, function()
		return #game.ctx.pools.sites == 0
	end, 60 * 600)

	local buildings = game.ctx.pools.buildings
	assertEqual(5, #buildings, "the storage facility and one per facing")
	-- Sites finish in any order, so find each building by its facing.
	local byFacing = {}
	for i = 2, #buildings do
		byFacing[buildings[i].facing] = buildings[i]
	end
	for _, facing in ipairs({ "N", "E", "S", "W" }) do
		local b = assert(byFacing[facing], "a building facing " .. facing)
		assertEqual(spots[facing][1], b.tileX)
		assertEqual(spots[facing][2], b.tileY)
		assertEqual(2, #b.ports)
		for _, port in ipairs(b.ports) do
			assertEqual(port, World.portAt(world, port.x, port.y))
		end
	end
	Capture.capture("placed_all_facings")

	Fake.pickDesign(game, "works")
	game:mousemoved(screenOf(game, c, 12.5, 18))
	assertTrue(WorldScreen.ghost(screen).ok, "expected a valid ghost on grass")
	Capture.capture("ghost_valid")

	game:mousemoved(screenOf(game, c, 4.5, 18))
	assertFalse(WorldScreen.ghost(screen).ok, "expected an invalid ghost on water")
	assertEqual("Can't place: it would stand on water", WorldScreen.status(screen))
	Capture.capture("ghost_invalid")
end)
