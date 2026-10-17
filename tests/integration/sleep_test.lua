-- A bed through the real input path: a design with a bed brick is built in
-- the builder, placed in the world, and a tired villager sleeps in it
-- (docs/CONTEXT.md "Bed"). The palette button, save, placement and the
-- sleeper all go through src/app/flow.lua.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local BuilderScreen = require("src.app.screens.builder")
local BuilderCamera = require("src.app.builder_camera")
local Config = require("src.game.config")
local World = require("src.game.world")
local Session = require("src.game.session")

local TILE = Config.tileSize

local function pixelOf(builder, x, y, z)
	return BuilderCamera.project(BuilderScreen.view(builder), x, y, z)
end

local function button(builder, label)
	for _, b in ipairs(BuilderScreen.buttons(builder)) do
		if b.label == label then
			return b.x + b.width / 2, b.y + b.height / 2
		end
	end
	error("no sidebar button " .. label)
end

test("a design with a bed, built in the builder, sleeps a tired villager", function()
	_G.love = LoveMock.new()
	local game = GameHarness.startSession(World.new(20, 20), { storage = Config.stockpile })
	local c = game.ctx.pools.characters[1]
	Fake.tap(game, "b")
	local builder = game.flow.builder

	Fake.click(game, 1, button(builder, "Width +"))
	for _, b in ipairs({ { "Bed", 3, 1 }, { "Output port", 7, 3.5 } }) do
		Fake.click(game, 1, button(builder, b[1]))
		Fake.click(game, 1, pixelOf(builder, b[2], b[3], 0))
	end
	Fake.click(game, 1, button(builder, "Name"))
	Fake.typeText(game, "Bunk")
	Fake.tap(game, "return")
	Fake.click(game, 1, button(builder, "Save"))
	assertEqual(1, #builder.library.designs, builder.message or "saved")
	Fake.tap(game, "escape")
	assertEqual("world", game.flow.screen)

	-- Place it, paying from the stockpile, and finish the site.
	Fake.tap(game, "1")
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
