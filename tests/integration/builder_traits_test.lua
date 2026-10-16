-- Function bricks, traits, cost and design rules through the real input
-- path: sidebar clicks and clicks on the draft go through src/app/flow.lua
-- to the builder screen, whose info panel (BuilderScreen.info) is what the
-- sidebar draws.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local BuilderScreen = require("src.app.screens.builder")
local BuilderCamera = require("src.app.builder_camera")
local Config = require("src.game.config")

local function openBuilder()
	_G.love = LoveMock.new()
	local game = GameHarness.startSession({ width = 20, height = 20 }, { storage = Config.stockpile })
	Fake.tap(game, "b")
	return game, game.flow.builder
end

local function pixelOf(builder, x, y, z)
	local sx, sy = BuilderCamera.project(BuilderScreen.view(builder), x, y, z)
	return sx, sy
end

local function button(builder, label)
	for _, b in ipairs(BuilderScreen.buttons(builder)) do
		if b.label == label then
			return b.x + b.width / 2, b.y + b.height / 2
		end
	end
	error("no sidebar button " .. label)
end

-- Picks `label` in the sidebar, then clicks the draft at stud (x, y) on
-- layer z.
local function placeAt(game, builder, label, x, y, z)
	Fake.click(game, 1, button(builder, label))
	local before = #builder.draft.bricks
	Fake.click(game, 1, pixelOf(builder, x, y, z or 0))
	assertEqual(before + 1, #builder.draft.bricks, "expected " .. label .. " placed at " .. x .. "," .. y)
end

local function costRow(info, item)
	for _, row in ipairs(info.cost) do
		if row.item == item then
			return row
		end
	end
	return nil
end

test("placing a stone brick raises health and lowers productivity in the sidebar", function()
	local game, builder = openBuilder()
	placeAt(game, builder, "2x2", 1, 1)
	local before = BuilderScreen.info(builder).traits
	Fake.click(game, 1, button(builder, "Stone"))
	placeAt(game, builder, "1x1", 3.5, 3.5)
	local after = BuilderScreen.info(builder).traits
	assertTrue(after.health > before.health, "health rises")
	assertTrue(after.productivity < before.productivity, "productivity falls")
end)

test("the cost counts bricks and baseplate against storage, short where it falls short", function()
	local game, builder = openBuilder()
	placeAt(game, builder, "2x2", 1, 1)
	local row = costRow(BuilderScreen.info(builder), "plank")
	assertEqual(Config.costs.baseplatePerTile.plank + 4 * Config.costs.perStud.plank.plank, row.need)
	assertEqual(Config.stockpile.plank, row.have)
	assertFalse(row.short)

	game.ctx.pools.characters[1].inventory.counts.plank = 1000 -- the inventory doesn't count
	game.ctx.pools.buildings[1].storage.counts.plank = 1
	row = costRow(BuilderScreen.info(builder), "plank")
	assertEqual(1, row.have)
	assertTrue(row.short, "expected the plank cost marked short")
end)

test("each broken rule is listed, and save is refused until the draft keeps them all", function()
	local game, builder = openBuilder()
	local input = Fake.FakeInput.new()
	Fake.click(game, 1, button(builder, "Width +"))
	Fake.click(game, 1, button(builder, "Depth +"))
	placeAt(game, builder, "Saw bench", 4, 4)
	assertEqual(BuilderScreen.PROBLEMS["no output port"], BuilderScreen.info(builder).problems[1])
	assertEqual(BuilderScreen.PROBLEMS["saw bench without input"], BuilderScreen.info(builder).problems[2])

	Fake.click(game, 1, button(builder, "Save"))
	assertEqual(0, #builder.library.designs)
	assertEqual(BuilderScreen.PROBLEMS["no output port"], builder.message)

	-- A port on the bench's top is above ground.
	placeAt(game, builder, "Output port", 4, 3.5, 3)
	assertEqual(BuilderScreen.PROBLEMS["port off edge"], BuilderScreen.info(builder).problems[1])
	Fake.click(game, 1, button(builder, "Save"))
	assertEqual(0, #builder.library.designs)

	-- Undo the stray port; put both ports on the south edge.
	input:press("lctrl")
	Fake.tap(game, "z")
	input:release("lctrl")
	placeAt(game, builder, "Output port", 1, 7.5)
	placeAt(game, builder, "Input port", 6, 7.5)
	assertEqual(0, #BuilderScreen.info(builder).problems)
	Fake.click(game, 1, button(builder, "Save"))
	assertEqual(1, #builder.library.designs)
end)
