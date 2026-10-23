-- The script builder's library manager (top bar 7) under real LÖVE 12:
-- save a design, rename it, duplicate it and delete the copy, with the
-- panel and its thumbnails drawn. Uses test-only design and prefab
-- folders, cleared first (docs/memory/e2e-isolate-save-dir.md). Captures
-- land in tests/screenshots/design_library_test/.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local Fake = require("tests.support.fake_input")
local FrameStepper = require("tests.support.frame_stepper")
local Config = require("src.game.config")
local DesignStore = require("src.app.design_store")
local ScriptBuilderScreen = require("src.app.screens.script_builder")

local SHED = [[
return group{ id = "root",
	box{ id = "floor", size = { 2, 2, 0.125 } },
	box{ id = "hut", size = { 1, 1, 1 }, transform = { move = { 0.5, 0.5, 0.125 } } },
}
]]

local function testConfig()
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.designs = { dir = "e2e_library_designs", prefabDir = "e2e_library_prefabs" }
	config.save = { file = "e2e_library_world.save", seed = Config.save.seed }
	config.scriptBuilder = {}
	for k, v in pairs(Config.scriptBuilder) do
		config.scriptBuilder[k] = v
	end
	config.scriptBuilder.testDesign = "e2e_shed.lua"
	return config
end

local function clear(config)
	for _, dir in ipairs({ config.designs.dir, config.designs.prefabDir }) do
		for _, name in ipairs(love.filesystem.getDirectoryItems(dir)) do
			love.filesystem.remove(dir .. "/" .. name)
		end
	end
	love.filesystem.remove(config.save.file)
end

local function clickAt(game, r)
	Fake.click(game, 1, r.x + r.width / 2, r.y + r.height / 2)
end

-- The test's own rows (named e2e_*), so the built-in list can grow.
local function names(screen)
	local out = {}
	for _, row in ipairs(ScriptBuilderScreen.libraryPanel(screen).rows) do
		if row.entry.name:match("^e2e_") then
			out[#out + 1] = row.entry.name
		end
	end
	return table.concat(out, ",")
end

-- Clicks button `action` on the row of `name`.
local function press(game, screen, name, action)
	for _, row in ipairs(ScriptBuilderScreen.libraryPanel(screen).rows) do
		if row.entry.name == name then
			for _, button in ipairs(row.buttons) do
				if button.action == action then
					clickAt(game, button)
					return
				end
			end
		end
	end
	error("no " .. action .. " on " .. name)
end

test("save, rename, duplicate and delete a design from the library panel", function()
	local config = testConfig()
	clear(config)
	assert(DesignStore.write(config.designs, "designs", "e2e_shed", SHED))
	local game = GameHarness.startSession({ width = 20, height = 20 }, { real = true, config = config })
	Fake.tap(game, "b")
	local screen = game.flow.scriptBuilder
	assertEqual("e2e_shed", screen.name)
	local input = Fake.FakeInput.new()
	input:press("lctrl")
	Fake.tap(game, "s")
	input:release("lctrl")
	assertTrue(screen.status and screen.status:find("Saved", 1, true), tostring(screen.status))

	Fake.tap(game, "7")
	FrameStepper.step(game, 1)
	Capture.capture("panel_open")
	press(game, screen, "e2e_shed", "rename")
	for _ = 1, #"e2e_shed" do
		Fake.tap(game, "backspace")
	end
	Fake.typeText(game, "e2e_barn")
	Fake.tap(game, "return")
	assertEqual("e2e_barn", screen.name)
	assertEqual(nil, love.filesystem.getInfo(config.designs.dir .. "/e2e_shed.lua"))
	assertEqual(SHED, love.filesystem.read(config.designs.dir .. "/e2e_barn.lua"))

	press(game, screen, "e2e_barn", "duplicate")
	assertEqual("e2e_barn,e2e_barn_copy", names(screen))
	press(game, screen, "e2e_barn_copy", "delete")
	FrameStepper.step(game, 1)
	Capture.capture("delete_armed")
	press(game, screen, "e2e_barn_copy", "delete")
	assertEqual("e2e_barn", names(screen))
	assertEqual(nil, love.filesystem.getInfo(config.designs.dir .. "/e2e_barn_copy.lua"))
	FrameStepper.step(game, 1)
	Capture.capture("after_delete")
	clear(config)
end)
