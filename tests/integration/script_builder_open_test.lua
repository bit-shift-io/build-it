-- The script builder through the real input path (src/app/flow.lua): B opens
-- it on the test design file, run through the sandbox; Esc goes back to the
-- world.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")

local function startGame()
	_G.love = LoveMock.new()
	return GameHarness.startSession({ width = 20, height = 20 })
end

test("B opens the script builder on the test design, and Esc returns to the world", function()
	local game = startGame()
	Fake.tap(game, "b")
	assertEqual("scriptBuilder", game.flow.screen)
	local screen = game.flow.scriptBuilder
	assertEqual(nil, screen.message, screen.message)
	assertTrue(#screen.triangles > 0, "expected the test design's geometry")
	assertTrue(screen.footprint.width >= 1, "expected a footprint")
	Fake.tap(game, "escape")
	assertEqual("world", game.flow.screen)
end)

test("Shift+B opens the script builder too: the brick builder is gone", function()
	local game = startGame()
	local input = Fake.FakeInput.new()
	input:press("lshift")
	Fake.tap(game, "b")
	input:release("lshift")
	assertEqual("scriptBuilder", game.flow.screen)
end)

-- A config whose test design is `name` in the save directory, holding `text`.
local function withDesign(name, text)
	local Config = require("src.game.config")
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.scriptBuilder = { testDesign = name }
	for k, v in pairs(Config.scriptBuilder) do
		config.scriptBuilder[k] = config.scriptBuilder[k] or v
	end
	love.filesystem.write(name, text)
	return config
end

test("a design that loops forever shows a budget message, and the game keeps running", function()
	_G.love = LoveMock.new()
	local config = withDesign("loop.lua", "while true do end")
	local game = GameHarness.startSession({ width = 20, height = 20 }, { config = config })
	Fake.tap(game, "b")
	local screen = game.flow.scriptBuilder
	assertEqual("scriptBuilder", game.flow.screen)
	assertTrue(screen.message and screen.message:find("budget", 1, true), tostring(screen.message))
	assertEqual(0, #screen.triangles)
	Fake.tap(game, "escape")
	assertEqual("world", game.flow.screen)
end)

test("a design that reaches for os shows an error instead of geometry", function()
	_G.love = LoveMock.new()
	local config = withDesign("escape.lua", 'os.execute("echo hi")\nreturn box{}')
	local game = GameHarness.startSession({ width = 20, height = 20 }, { config = config })
	Fake.tap(game, "b")
	local screen = game.flow.scriptBuilder
	assertTrue(screen.message and screen.message:find("escape.lua:1:", 1, true), tostring(screen.message))
	assertEqual(nil, screen.footprint)
end)

test("a design placing the input port prefab shows the port snapped to the nearest footprint edge", function()
	_G.love = LoveMock.new()
	local config = withDesign("port.lua", [[
		return group{ box{ size = { 2, 2, 1 } },
			prefab("input_port", { transform = { move = { 0.75, 0.75, 0 } } }) }
	]])
	local game = GameHarness.startSession({ width = 20, height = 20 }, { config = config })
	Fake.tap(game, "b")
	local screen = game.flow.scriptBuilder
	assertEqual(nil, screen.message, screen.message)
	assertEqual(1, #screen.ports)
	local port = screen.ports[1]
	assertEqual("input", port.kind)
	assertEqual("N", port.edge)
	assertEqual(1, port.x)
	assertEqual(0.5, port.y)
end)
