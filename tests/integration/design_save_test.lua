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
local Library = require("src.game.designs.library")
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
		return b.kind == "expand" and b.value == id
	end
end

-- A predicate for the version row button of `kind` ("openVersion" or
-- "deleteVersion") for version `n` of design `id`.
local function versionButton(kind, id, n)
	return function(b)
		return b.kind == kind and b.value == id and b.version == n
	end
end

-- The version numbers the Open list shows for design `id`, top to bottom.
local function listedVersions(builder, id)
	local out = {}
	for _, b in ipairs(BuilderScreen.buttons(builder)) do
		if b.kind == "openVersion" and b.value == id then
			table.insert(out, b.version)
		end
	end
	return out
end

-- Makes the draft a valid design (src/game/builder/validate.lua) away from
-- the studs the tests click: the baseplate grows to 2x1 tiles, and a saw
-- and an output port go on its east tile. Returns how many bricks it added.
local EXTRA = 2
local function makeValid(game, builder)
	Fake.click(game, 1, button(builder, "Width +"))
	for _, b in ipairs({ { "Saw", 6.5, 0.5 }, { "Output port", 7, 3.5 } }) do
		Fake.click(game, 1, button(builder, b[1]))
		Fake.click(game, 1, pixelOf(builder, b[2], b[3], 0))
	end
	Fake.click(game, 1, button(builder, "2x2"))
	return EXTRA
end

local function nameDesign(game, builder, name)
	Fake.click(game, 1, button(builder, "Name"))
	Fake.typeText(game, name)
	Fake.tap(game, "return")
end

test("save, edit, save again, relaunch: the design keeps both versions", function()
	local game, builder = launch()
	makeValid(game, builder)
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
	assertEqual(1 + EXTRA, #design.versions[1].bricks, "expected version 1 intact")
	assertEqual(2 + EXTRA, #design.versions[2].bricks)

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
	makeValid(game, builder)
	Fake.click(game, 1, pixelOf(builder, 2, 2, 0))
	nameDesign(game, builder, "Hut")
	Fake.click(game, 1, button(builder, "Save"))
	local id = builder.library.designs[1].id

	-- A second, unrelated design.
	Fake.click(game, 1, button(builder, "New"))
	assertEqual(0, #builder.draft.bricks)
	assertEqual("", builder.name)
	makeValid(game, builder)
	Fake.click(game, 1, pixelOf(builder, 2, 2, 0))
	Fake.click(game, 1, pixelOf(builder, 2, 2, 1))
	nameDesign(game, builder, "Tower")
	Fake.click(game, 1, button(builder, "Save"))
	assertEqual(2, #builder.library.designs)

	game, builder, input = launch(love.filesystem.getSaveDirectory())
	Fake.click(game, 1, button(builder, "Open"))
	Fake.click(game, 1, button(builder, designButton(id)))
	Fake.click(game, 1, button(builder, versionButton("openVersion", id, 1)))
	assertEqual("Hut", builder.name)
	assertEqual(1 + EXTRA, #builder.draft.bricks)

	-- Undo never reaches back past the open into another design.
	input:press("lctrl")
	Fake.tap(game, "z")
	input:release("lctrl")
	assertEqual(1 + EXTRA, #builder.draft.bricks, "expected opening to start a fresh undo history")

	Fake.click(game, 1, pixelOf(builder, 2, 2, 1))
	Fake.click(game, 1, button(builder, "Save"))
	local design = builder.library.designs[1]
	assertEqual(id, design.id)
	assertEqual(2, #design.versions)
	assertEqual(1 + EXTRA, #design.versions[1].bricks)
	assertEqual(2 + EXTRA, #design.versions[2].bricks)
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
	makeValid(game, builder)
	Fake.click(game, 1, button(builder, "Save"))
	assert(love.filesystem.write(DIR .. "/d9.design", "build-it-design 1\nbrick x=n:0\n"))

	_, builder = launch(love.filesystem.getSaveDirectory())
	assertEqual(1, #builder.library.designs)
	assertEqual(1, #builder.problems)
	assertEqual("d9.design", builder.problems[1].name)
	assertTrue(builder.message ~= nil, "expected the bad file reported on screen")
end)

-- Saves a valid design named `name` as three versions, each one brick
-- taller. Returns its id.
local function saveThreeVersions(game, builder, name)
	makeValid(game, builder)
	nameDesign(game, builder, name)
	for z = 0, 2 do
		Fake.click(game, 1, pixelOf(builder, 2, 2, z))
		Fake.click(game, 1, button(builder, "Save"))
	end
	return builder.designId
end

local function expand(game, builder, id)
	Fake.click(game, 1, button(builder, "Open"))
	Fake.click(game, 1, button(builder, designButton(id)))
end

local function same(expected, actual, what)
	assertEqual(table.concat(expected, ","), table.concat(actual, ","), what)
end

test("expand a design, delete v2 with two clicks: the list shows v3 and v1, and a relaunch keeps it deleted", function()
	local game, builder = launch()
	local id = saveThreeVersions(game, builder, "Saw mill")
	expand(game, builder, id)
	same({ 3, 2, 1 }, listedVersions(builder, id), "expected live versions newest first")

	Fake.click(game, 1, button(builder, versionButton("deleteVersion", id, 2)))
	same({ 3, 2, 1 }, listedVersions(builder, id), "expected one click only to arm the delete")
	Fake.click(game, 1, button(builder, versionButton("deleteVersion", id, 2)))
	same({ 3, 1 }, listedVersions(builder, id))
	assertEqual("Deleted Saw mill v2.", builder.message)

	game, builder = launch(love.filesystem.getSaveDirectory())
	expand(game, builder, id)
	same({ 3, 1 }, listedVersions(builder, id), "expected the delete to survive a relaunch")
end)

test("a Delete click then another button click deletes nothing", function()
	local game, builder = launch()
	local id = saveThreeVersions(game, builder, "Saw mill")
	expand(game, builder, id)
	Fake.click(game, 1, button(builder, versionButton("deleteVersion", id, 2)))
	assertEqual("Click again to delete Saw mill v2.", builder.message)
	Fake.click(game, 1, button(builder, versionButton("deleteVersion", id, 3)))
	Fake.click(game, 1, button(builder, versionButton("deleteVersion", id, 2)))
	same({ 3, 2, 1 }, listedVersions(builder, id), "expected another row's click to disarm v2")
	Fake.click(game, 1, button(builder, "Width +"))
	Fake.click(game, 1, button(builder, versionButton("deleteVersion", id, 2)))
	same({ 3, 2, 1 }, listedVersions(builder, id), "expected another button's click to disarm")
end)

local function deleteTwice(game, builder, id, n)
	Fake.click(game, 1, button(builder, versionButton("deleteVersion", id, n)))
	Fake.click(game, 1, button(builder, versionButton("deleteVersion", id, n)))
end

test("delete the version the draft came from, then Save: the draft saves as the next version", function()
	local game, builder = launch()
	local id = saveThreeVersions(game, builder, "Saw mill")
	expand(game, builder, id)
	Fake.click(game, 1, button(builder, versionButton("openVersion", id, 2)))
	local bricks = #builder.draft.bricks
	Fake.click(game, 1, button(builder, "Open"))
	same({ 3, 2, 1 }, listedVersions(builder, id), "expected the list to reopen expanded")
	deleteTwice(game, builder, id, 2)
	assertEqual(bricks, #builder.draft.bricks, "expected the draft kept")
	assertEqual(id, builder.designId)

	Fake.click(game, 1, button(builder, "Save"))
	local design = builder.library.designs[1]
	assertEqual(1, #builder.library.designs)
	assertEqual(4, #design.versions, "expected v4, never v2 again")
	assertEqual(bricks, #design.versions[4].bricks)
	same({ 4, 3, 1 }, listedVersions(builder, id))
end)

test("delete every version of the open design, then Save: a new design with a new id", function()
	local game, builder = launch()
	local id = saveThreeVersions(game, builder, "Saw mill")
	local bricks = #builder.draft.bricks
	expand(game, builder, id)
	for n = 3, 1, -1 do
		deleteTwice(game, builder, id, n)
	end
	assertEqual("Deleted Saw mill v1.", builder.message)
	for _, b in ipairs(BuilderScreen.buttons(builder)) do
		assertFalse(b.kind == "expand" and b.value == id, "expected the deleted design hidden")
	end
	assertEqual(bricks, #builder.draft.bricks, "expected the draft kept")

	Fake.click(game, 1, button(builder, "Save"))
	assertEqual(2, #builder.library.designs)
	assertTrue(builder.designId ~= id, "expected a new id")
	assertEqual("Saw mill", builder.name)

	game, builder = launch(love.filesystem.getSaveDirectory())
	Fake.click(game, 1, button(builder, "Open"))
	local listed = {}
	for _, b in ipairs(BuilderScreen.buttons(builder)) do
		if b.kind == "expand" then
			table.insert(listed, b.value)
		end
	end
	assertEqual(1, #listed)
	assertTrue(listed[1] ~= id, "expected the deleted design to stay hidden after a relaunch")
end)

test("a failed design file write shows the error and leaves the version live", function()
	local game, builder = launch()
	local id = saveThreeVersions(game, builder, "Saw mill")
	expand(game, builder, id)
	-- The disk refuses every write.
	love.filesystem.write = function()
		return false, "disk full"
	end
	deleteTwice(game, builder, id, 2)
	assertEqual("Could not delete: disk full", builder.message)
	same({ 3, 2, 1 }, listedVersions(builder, id), "expected v2 still listed")
	assertTrue(Library.isLive(Library.design(builder.library, id), 2), "expected memory to match disk")
end)
