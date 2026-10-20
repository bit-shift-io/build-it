-- World save and load through the real input path: play a session (place a
-- woodcutter, let it work, walk, harvest), save with F5 or by quitting,
-- then relaunch over the same save directory and pick Continue on the
-- title screen. love_mock backs love.filesystem with a real temporary save
-- directory, so a relaunch is a fresh flow over the same files.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local DesignStore = require("src.app.design_store")
local TitleScreen = require("src.app.screens.title")
local SaveCodec = require("src.game.save.codec")
local Session = require("src.game.session")

local TILE = Config.tileSize

-- A plank saw on the north row of a 2x1 tile baseplate and an output port
-- on its south edge under tile (1, 0).
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

-- Plays a session in a 20x20 world with trees north-east of the
-- character: places the woodcutter (footprint (12..13, 7)), lets it work,
-- then walks and hand-harvests a while. Returns the game.
local function play()
	_G.love = LoveMock.new()
	assert(DesignStore.write(Config.designs.dir, WOODCUTTER))
	local world = World.new(20, 20)
	World.setTerrain(world, 2, 2, "water")
	local id = 0
	for y = 4, 6 do
		for _, x in ipairs({ 11, 14 }) do
			id = id + 1
			World.addNode(world, { id = id, kind = "tree", tileX = x, tileY = y, variant = id, stage = 1, amount = Config.nodes.tree.amount })
		end
	end
	local game = GameHarness.startSession(world, { storage = Config.stockpile })
	local villager = Session.newVillager(1, 5.5 * TILE, 12.5 * TILE, Config)
	villager.name = "Ada"
	table.insert(game.ctx.pools.villagers, villager)
	local input = Fake.FakeInput.new()
	local c = game.ctx.pools.characters[1]
	Fake.tap(game, "1")
	Fake.tap(game, "return")
	Fake.click(game, 1, 640 + (13 * TILE - c.x), 360 + (7.5 * TILE - c.y))
	GameHarness.completeSites(game)
	assert(game.ctx.pools.buildings[2], "fixture: the woodcutter was placed")
	Fake.holdFor(game, input, "d", 0.4)
	Fake.holdFor(game, input, "w", 2.2) -- up beside the trees in column 11
	Fake.holdFor(game, input, "e", 1.3)
	Fake.holdFor(game, input, "a", 0.15)
	return game
end

-- Relaunches over the current save directory, on the title screen.
local function relaunch()
	_G.love = LoveMock.new({ saveDir = love.filesystem.getSaveDirectory() })
	return GameHarness.launch()
end

local function optionIds(title)
	local ids = {}
	for _, option in ipairs(TitleScreen.options(title)) do
		ids[#ids + 1] = option.id
	end
	return table.concat(ids, ",")
end

test("F5 saves; relaunch offers Continue, which restores the session exactly", function()
	local game = play()
	game:keypressed("f5")
	local saved = SaveCodec.encode(game.ctx)
	local b = game.ctx.pools.buildings[2]
	assertTrue(b.functionBricks[1].node ~= nil, "fixture: the saw holds a reservation")

	local again = relaunch()
	assertEqual("title", again.flow.screen)
	assertEqual("continue,new", optionIds(again.flow.title))
	again:keypressed("return") -- Continue is the first option; no frame runs yet
	assertEqual("world", again.flow.screen)
	local ctx = again.flow.ctx
	assertTrue(ctx ~= nil, "expected a session")
	assertEqual(saved, SaveCodec.encode(ctx), "expected the loaded session to equal the saved one")
	assertEqual(2, #ctx.pools.buildings, "the storage facility and the woodcutter")
	assertEqual("d1", ctx.pools.buildings[2].design.id)
	assertTrue(again.flow.world.player == ctx.pools.characters[1], "expected the world screen on the loaded character")
	assertTrue(again.camera == again.flow.world.camera, "expected the harness camera to follow the new world screen")
	Fake.runUntil(again, function()
		return ctx.time > game.ctx.time + 1
	end, 120)
end)

test("quitting autosaves; Continue after relaunch restores the session", function()
	local game = play()
	assertFalse(love.filesystem.getInfo(Config.save.file), "fixture: nothing saved yet")
	game:quit()
	local saved = SaveCodec.encode(game.ctx)

	local again = relaunch()
	again:keypressed("return")
	assertEqual(saved, SaveCodec.encode(again.ctx))
	for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
		assertFalse(name:match("%.tmp$"), "expected no temp file left behind: " .. name)
	end
end)

test("a building whose design is gone from the library loads from the save's snapshot", function()
	local game = play()
	game:keypressed("f5")
	assertTrue(love.filesystem.remove(Config.designs.dir .. "/d1.design"), "fixture: removed the design file")

	local again = relaunch()
	assertEqual(0, #again.flow.library.designs, "expected the library to have lost the design")
	again:keypressed("return")
	assertEqual("world", again.flow.screen)
	local b = again.ctx.pools.buildings[2]
	assertEqual("Woodcutter", b.design.name)
	assertEqual(#WOODCUTTER.versions[1].bricks, #b.design.versions[b.version].bricks)
	Fake.runUntil(again, function()
		return b.full
	end, 60 * 60)
end)

test("with no save the title offers only New game, which starts the seeded world", function()
	_G.love = LoveMock.new()
	local game = GameHarness.launch()
	assertEqual("new", optionIds(game.flow.title))
	assertEqual(nil, game.ctx)
	Fake.tap(game, "return")
	assertEqual("world", game.flow.screen)
	assertEqual(Config.world.width, game.ctx.world.width)
	assertEqual(Config.save.seed, game.ctx.seed)
	assertTrue(#game.ctx.pools.nodes > 0, "expected a generated world with nodes")
	assertEqual(1, #game.ctx.pools.buildings, "expected the starting storage facility")
end)

test("an unreadable save keeps the title up with the reason; New game still works", function()
	_G.love = LoveMock.new()
	assert(love.filesystem.write(Config.save.file, "build-it-save 2\nmystery a=n:1\n"))
	local game = GameHarness.launch()
	assertEqual("continue,new", optionIds(game.flow.title))
	Fake.tap(game, "return")
	assertEqual("title", game.flow.screen)
	assertTrue(game.flow.title.message ~= nil, "expected the reason on screen")
	Fake.tap(game, "down")
	Fake.tap(game, "return")
	assertEqual("world", game.flow.screen)
end)

test("clicking an option picks it", function()
	_G.love = LoveMock.new()
	local game = GameHarness.launch()
	local b = TitleScreen.buttons(game.flow.title)[1]
	Fake.click(game, 1, b.x + b.width / 2, b.y + b.height / 2)
	assertEqual("world", game.flow.screen)
end)
