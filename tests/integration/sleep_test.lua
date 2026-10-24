-- A bed through the real input path: a design with the bed prefab, written
-- by hand as a Lua file, is placed from the picker, and a tired villager
-- sleeps in it (docs/CONTEXT.md "Bed"); in the starter bedhouse the sleeper
-- walks in through the door. Placement and the sleeper go through
-- src/app/flow.lua.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local DesignStore = require("src.app.design_store")
local Config = require("src.game.config")
local World = require("src.game.world")
local Session = require("src.game.session")
local Walls = require("tests.support.walls")

local TILE = Config.tileSize

-- A 2x1 bunk house: a floor, the bed prefab and an output port.
local BUNK = [[
return group{ id = "root", name = "Bunk",
	box{ id = "floor", size = { 2, 1, 0.125 } },
	prefab("bed", { id = "bed", transform = { move = { 0.25, 0.25, 0.125 } } }),
	prefab("output_port", { id = "out", transform = { move = { 1.25, 0.75, 0 } } }),
}
]]

test("a design with a bed, placed from the picker, sleeps a tired villager", function()
	_G.love = LoveMock.new()
	assert(DesignStore.write(Config.designs, "designs", "bunk", BUNK))
	local game = GameHarness.startSession(World.new(20, 20), { storage = Config.stockpile })
	local c = game.ctx.pools.characters[1]

	-- Place it, paying from the stockpile, and finish the site.
	Fake.pickDesign(game, "bunk")
	local sx, sy = 640 + (13 * TILE - c.x), 360 + (9 * TILE - c.y)
	game:mousemoved(sx, sy, 0, 0)
	Fake.click(game, 1, sx, sy)
	local site = game.ctx.pools.sites[1]
	assertTrue(site ~= nil, "placed a site")
	GameHarness.completeSites(game)
	local building = game.ctx.pools.buildings[2]
	local bed = building.functionBricks[1]
	assertTrue(bed.bed, "the building has a bed")

	local v = Session.newVillager(1, 5.5 * TILE, 5.5 * TILE, Config)
	v.name = "Ada"
	table.insert(game.ctx.pools.villagers, v)
	v.needs.tiredness = Config.needs.tiredAt
	for _ = 1, 60 * 20 do
		game:update(1 / 60)
		if bed.occupant and bed.occupant.stage == "sleeping" then
			break
		end
	end
	assertEqual(v.job, bed.occupant)
	assertEqual("sleeping", v.job.stage)

	for _ = 1, 60 * 90 do
		game:update(1 / 60)
		if not v.job then
			break
		end
	end
	assertEqual(nil, v.job)
	assertTrue(v.needs.tiredness < 0.01, "rested")
	assertEqual(nil, bed.occupant)
end)

test("a tired villager walks in through the starter bedhouse's door to its bed, never through a wall", function()
	_G.love = LoveMock.new()
	local game = GameHarness.startSession(World.new(20, 20), { storage = Config.stockpile })
	local c = game.ctx.pools.characters[1]

	Fake.pickDesign(game, "bedhouse")
	local sx, sy = 640 + (13 * TILE - c.x), 360 + (9 * TILE - c.y)
	game:mousemoved(sx, sy, 0, 0)
	Fake.click(game, 1, sx, sy)
	GameHarness.completeSites(game)
	local house = game.ctx.pools.buildings[2]
	assert(house and house.design == "bedhouse", "the bedhouse was placed")

	-- North of the house: its door is in the south wall.
	local v = Session.newVillager(1, (house.tileX + 0.5) * TILE, (house.tileY - 3.5) * TILE, Config)
	table.insert(game.ctx.pools.villagers, v)
	v.needs.tiredness = Config.needs.tiredAt
	Fake.runUntil(game, function()
		local inWall = Walls.villagerInWall(game.ctx)
		assert(not inWall, inWall)
		return v.job ~= nil and v.job.kind == "sleep" and v.job.stage == "sleeping"
	end, 60 * 30)
	local bed = v.job.brick
	assertTrue(bed.bed and bed.occupant == v.job, "asleep in a bed")
	assertEqual(house, World.buildingAt(game.ctx.world, math.floor(v.x / TILE), math.floor(v.y / TILE)), "inside the house")
	local d = math.max(math.abs(v.x / TILE - bed.pointX), math.abs(v.y / TILE - bed.pointY))
	assertTrue(d <= 0.5, "beside its bed, " .. d .. " tiles off")
end)
