-- The design library under real LÖVE 12: a design saved through the
-- builder survives a relaunch, and each of its versions bakes 4 facings.
-- Captures land in tests/screenshots/design_library_test/: the builder
-- sidebar's Design section, the Open list, and every facing of both
-- versions.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local Model = require("src.game.blocks.model")
local BuilderScreen = require("src.app.screens.builder")
local BuilderCamera = require("src.app.builder_camera")
local DesignCache = require("src.app.bake.design_cache")

-- A config whose design library lives in its own save-directory folder, so
-- the test never touches the player's real designs.
local function configWithDesignDir(dir)
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.designs = { dir = dir, maxNameLength = Config.designs.maxNameLength }
	return config
end

local function clearDir(dir)
	for _, name in ipairs(love.filesystem.getDirectoryItems(dir)) do
		love.filesystem.remove(dir .. "/" .. name)
	end
end

local function pixelOf(builder, x, y, z)
	return BuilderCamera.project(BuilderScreen.view(builder), x, y, z)
end

local function clickButton(game, builder, match)
	for _, b in ipairs(BuilderScreen.buttons(builder)) do
		if b.label == match or (b.kind == "design" and b.value == match) then
			Fake.click(game, 1, b.x + b.width / 2, b.y + b.height / 2)
			return
		end
	end
	error("no sidebar button " .. tostring(match))
end

local function launch(config)
	local game = GameHarness.startSession({ width = 20, height = 20 }, { real = true, config = config })
	Fake.tap(game, "b")
	return game, game.flow.builder
end

-- Whether `sprite` has any opaque pixel.
local function hasPixels(sprite)
	local data = love.graphics.readbackTexture(sprite.image)
	local w, h = data:getDimensions()
	for y = 0, h - 1, 2 do
		for x = 0, w - 1, 2 do
			local _, _, _, a = data:getPixel(x, y)
			if a > 0.5 then
				return true
			end
		end
	end
	return false
end

test("a saved design survives a relaunch and bakes 4 facings per version", function()
	local config = configWithDesignDir("e2e_designs")
	clearDir(config.designs.dir)

	local game, builder = launch(config)
	clickButton(game, builder, "Width +")
	-- A valid design (src/game/builder/validate.lua): a saw on the north
	-- edge and an output port on the south edge, both clear of the hall.
	clickButton(game, builder, "Saw")
	Fake.click(game, 1, pixelOf(builder, 1.5, 0.5, 0))
	clickButton(game, builder, "Output port")
	Fake.click(game, 1, pixelOf(builder, 7, 3.5, 0))
	clickButton(game, builder, "2x4")
	clickButton(game, builder, "paint:8")
	Fake.click(game, 1, pixelOf(builder, 4, 2, 0))
	assertEqual(3, #builder.draft.bricks)
	clickButton(game, builder, "Name")
	Fake.typeText(game, "Blue hall")
	Fake.tap(game, "return")
	clickButton(game, builder, "Save")
	-- Version 2: a red slope on top, off-centre so every facing differs.
	clickButton(game, builder, "slope")
	clickButton(game, builder, "Stone")
	clickButton(game, builder, "paint:1")
	Fake.click(game, 1, pixelOf(builder, 2, 2, 1))
	clickButton(game, builder, "Save")
	game:mousemoved(5, 5, 0, 0)
	Capture.capture("builder_saved")

	game, builder = launch(config)
	assertEqual(1, #builder.library.designs)
	local design = builder.library.designs[1]
	assertEqual("Blue hall", design.name)
	assertEqual(2, #design.versions)

	clickButton(game, builder, "Open")
	game:mousemoved(5, 5, 0, 0)
	Capture.capture("builder_open_list")
	clickButton(game, builder, design.id)
	assertEqual(4, #builder.draft.bricks)
	game:mousemoved(5, 5, 0, 0)
	Capture.capture("builder_opened")

	local cache = DesignCache.new(config)
	for n = 1, 2 do
		for _, facing in ipairs(Model.FACINGS) do
			local sprite = DesignCache.sprite(cache, design, n, facing, 2)
			assertTrue(hasPixels(sprite), string.format("expected v%d %s to draw something", n, facing))
			Capture.captureTexture(string.format("v%d_%s_x2", n, facing), sprite.image)
		end
	end
	-- Each version baked its 4 facings once, together.
	assertEqual(2, #cache.baked)
	local east = DesignCache.sprite(cache, design, 1, "E", 2)
	assertEqual(1, east.width, "expected the 2x1 tile hall turned east to stand 1 tile wide")
	assertEqual(2, east.depth)
end)
