-- Saving and opening designs through the real input path: sidebar clicks,
-- typed names (textinput) and keys go through src/app/flow.lua to the
-- builder screen, which writes the design library to the save directory.
-- love_mock backs love.filesystem with a real temporary save directory, so
-- a "relaunch" is a fresh session over the same directory.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local BuilderScreen = require("src.app.screens.builder")
local BuilderCamera = require("src.app.builder_camera")
local DesignStore = require("src.app.design_store")
local Config = require("src.game.config")

local DIR = Config.designs.dir

-- Starts the app over `saveDir` (a fresh one when nil) and opens the builder.
local function launch(saveDir)
	_G.love = LoveMock.new({ saveDir = saveDir })
	local game = GameHarness.startSession({ width = 20, height = 20 })
	local input = Fake.FakeInput.new()
	Fake.tap(game, "b")
	return game, game.flow.builder, input
end

local function pixelOf(builder, x, y, z)
	return BuilderCamera.project(BuilderScreen.view(builder), x, y, z)
end

-- The centre of the first sidebar button matching `match` (its label, or a
-- predicate on the button).
local function button(builder, match)
	for _, b in ipairs(BuilderScreen.buttons(builder)) do
		if b.label == match or (type(match) == "function" and match(b)) then
			return b.x + b.width / 2, b.y + b.height / 2
		end
	end
	error("no sidebar button " .. tostring(match))
end

local function designButton(id)
	return function(b)
		return b.kind == "design" and b.value == id
	end
end

local function nameDesign(game, builder, name)
	Fake.click(game, 1, button(builder, "Name"))
	Fake.typeText(game, name)
	Fake.tap(game, "return")
end

test("save, edit, save again, relaunch: the design keeps both versions", function()
	local game, builder = launch()
	Fake.click(game, 1, pixelOf(builder, 2, 2, 0))
	nameDesign(game, builder, "Hut")
	Fake.click(game, 1, button(builder, "Save"))
	assertEqual(1, #builder.library.designs)
	local id = builder.library.designs[1].id

	Fake.click(game, 1, pixelOf(builder, 2, 2, 1))
	Fake.click(game, 1, button(builder, "Save"))
	assertEqual(1, #builder.library.designs, "expected the second save to append to the same design")

	local saveDir = love.filesystem.getSaveDirectory()
	local _, relaunched = launch(saveDir)
	local design = relaunched.library.designs[1]
	assertEqual(1, #relaunched.library.designs)
	assertEqual(id, design.id)
	assertEqual("Hut", design.name)
	assertEqual(2, #design.versions)
	assertEqual(1, #design.versions[1].bricks, "expected version 1 intact")
	assertEqual(2, #design.versions[2].bricks)

	local fromDisk = DesignStore.load(DIR)
	assertEqual(2, #fromDisk.designs[1].versions)
	for _, name in ipairs(love.filesystem.getDirectoryItems(DIR)) do
		assertFalse(name:match("%.tmp$"), "expected no temp file left behind: " .. name)
	end
end)

test("an empty draft is refused with a message and writes nothing", function()
	local game, builder = launch()
	Fake.click(game, 1, button(builder, "Save"))
	assertEqual(0, #builder.library.designs)
	assertTrue(builder.message ~= nil, "expected a refusal message")
	assertEqual(0, #love.filesystem.getDirectoryItems(DIR))
end)

test("open a saved design, edit it, save: a new version, the old one intact", function()
	local game, builder, input = launch()
	Fake.click(game, 1, pixelOf(builder, 2, 2, 0))
	nameDesign(game, builder, "Hut")
	Fake.click(game, 1, button(builder, "Save"))
	local id = builder.library.designs[1].id

	-- A second, unrelated design.
	Fake.click(game, 1, button(builder, "New"))
	assertEqual(0, #builder.draft.bricks)
	assertEqual("", builder.name)
	Fake.click(game, 1, pixelOf(builder, 2, 2, 0))
	Fake.click(game, 1, pixelOf(builder, 2, 2, 1))
	nameDesign(game, builder, "Tower")
	Fake.click(game, 1, button(builder, "Save"))
	assertEqual(2, #builder.library.designs)

	game, builder, input = launch(love.filesystem.getSaveDirectory())
	Fake.click(game, 1, button(builder, "Open"))
	Fake.click(game, 1, button(builder, designButton(id)))
	assertEqual("Hut", builder.name)
	assertEqual(1, #builder.draft.bricks)

	-- Undo never reaches back past the open into another design.
	input:press("lctrl")
	Fake.tap(game, "z")
	input:release("lctrl")
	assertEqual(1, #builder.draft.bricks, "expected opening to start a fresh undo history")

	Fake.click(game, 1, pixelOf(builder, 2, 2, 1))
	Fake.click(game, 1, button(builder, "Save"))
	local design = builder.library.designs[1]
	assertEqual(id, design.id)
	assertEqual(2, #design.versions)
	assertEqual(1, #design.versions[1].bricks)
	assertEqual(2, #design.versions[2].bricks)
	assertEqual(1, #builder.library.designs[2].versions, "expected the other design untouched")
end)

test("typing a name never turns the brick, and Esc stops typing without leaving", function()
	local game, builder = launch()
	Fake.click(game, 1, button(builder, "Name"))
	Fake.typeText(game, "rr")
	Fake.tap(game, "r")
	Fake.tap(game, "r")
	assertEqual(0, builder.held.rotation)
	Fake.tap(game, "backspace")
	assertEqual("r", builder.name)
	Fake.tap(game, "escape")
	assertEqual("builder", game.flow.screen)
	Fake.tap(game, "r")
	assertEqual(1, builder.held.rotation, "expected R to turn the brick once typing stops")
	Fake.tap(game, "escape")
	assertEqual("world", game.flow.screen)
end)

test("a corrupt design file is reported at launch, and the rest still load", function()
	local game, builder = launch()
	Fake.click(game, 1, pixelOf(builder, 2, 2, 0))
	Fake.click(game, 1, button(builder, "Save"))
	assert(love.filesystem.write(DIR .. "/d9.design", "build-it-design 1\nbrick x=n:0\n"))

	_, builder = launch(love.filesystem.getSaveDirectory())
	assertEqual(1, #builder.library.designs)
	assertEqual(1, #builder.problems)
	assertEqual("d9.design", builder.problems[1].name)
	assertTrue(builder.message ~= nil, "expected the bad file reported on screen")
end)
