-- Params in the script builder through the real input path
-- (src/app/flow.lua): each UI.* param a design declares gets an input in
-- the params panel. A change re-runs the script and rebuilds the model
-- live, and saving writes the new default into the (locked) script.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local ScriptBuilderScreen = require("src.app.screens.script_builder")

-- A game in the script builder, opened on design file `name`.lua in the
-- save directory holding `text`.
local function openBuilder(name, text)
	_G.love = LoveMock.new()
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.scriptBuilder = {}
	for k, v in pairs(Config.scriptBuilder) do
		config.scriptBuilder[k] = v
	end
	config.scriptBuilder.testDesign = name .. ".lua"
	love.filesystem.write(name .. ".lua", text)
	local game = GameHarness.startSession({ width = 20, height = 20 }, { config = config })
	Fake.tap(game, "b")
	return game, game.flow.scriptBuilder
end

local function withCtrl(game, key)
	local input = Fake.FakeInput.new()
	input:press("lctrl")
	Fake.tap(game, key)
	input:release("lctrl")
end

-- The params panel row labelled `label`.
local function row(screen, label)
	for _, r in ipairs(ScriptBuilderScreen.paramsPanel(screen)) do
		if r.param.label == label then
			return r
		end
	end
	error("no param row " .. label)
end

local function clickOn(game, box)
	Fake.click(game, 1, box.x + box.width / 2, box.y + box.height / 2)
end

local SPHERE = "local radius = UI.number({ default = 3, step = 0.2 })\n"
	.. "return sphere{ id = \"ball\", radius = radius, transform = { move = { 0, 0, 3 } } }\n"

test("the sphere's radius stepper resizes the model live, and saving writes the new default", function()
	local game, screen = openBuilder("ball", SPHERE)
	assertEqual(nil, screen.message, screen.message)
	assertTrue(screen.locked, "a script with a param is locked")
	local before = screen.bounds.maxX - screen.bounds.minX
	local radius = row(screen, "radius")
	assertEqual(3, radius.param.value)
	clickOn(game, radius.plus)
	clickOn(game, row(screen, "radius").plus)
	assertEqual(nil, screen.message, screen.message)
	assertEqual(3.4, row(screen, "radius").param.value)
	assertNear(before + 0.8, screen.bounds.maxX - screen.bounds.minX, 0.05)
	clickOn(game, row(screen, "radius").minus)
	assertEqual(3.2, row(screen, "radius").param.value)
	withCtrl(game, "s")
	local saved = assert(love.filesystem.read(Config.designs.dir .. "/ball.lua"))
	assertEqual((SPHERE:gsub("default = 3,", "default = 3.2,")), saved)
end)

local KIT = "local width = UI.number({ default = 2, min = 1, max = 4 })\n"
	.. "local tall = UI.bool({})\n"
	.. "local shape = UI.choice({ options = { \"box\", \"wedge\" } })\n"
	.. "local h = tall and 3 or 1\n"
	.. "if shape == \"wedge\" then return wedge{ size = { width, 1, h } } end\n"
	.. "return box{ size = { width, 1, h } }\n"

test("a typed value clamps, digits typed pick no tool, a bool toggles and a choice steps", function()
	local game, screen = openBuilder("kit", KIT)
	assertEqual(nil, screen.message, screen.message)
	clickOn(game, row(screen, "width").value)
	assertTrue(ScriptBuilderScreen.modal(screen), "the text box holds the keyboard")
	Fake.tap(game, "backspace")
	Fake.typeText(game, "49")
	Fake.tap(game, "return")
	assertEqual("select", screen.tool, "digits typed in the box pick no tool")
	assertEqual(4, row(screen, "width").param.value, "49 clamps to max 4")
	assertNear(4, screen.bounds.maxX - screen.bounds.minX, 1e-6)
	clickOn(game, row(screen, "tall").value)
	assertEqual(true, row(screen, "tall").param.value)
	assertNear(3, screen.bounds.maxZ, 1e-6)
	clickOn(game, row(screen, "shape").value)
	assertEqual("wedge", row(screen, "shape").param.value)
	assertEqual(nil, screen.message, screen.message)
	clickOn(game, row(screen, "width").value)
	Fake.typeText(game, "x")
	Fake.tap(game, "return")
	assertTrue(screen.message ~= nil, "a bad value is refused with why")
	assertEqual(4, row(screen, "width").param.value)
end)
