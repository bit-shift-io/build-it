-- Materials and texture variants under real LÖVE 12: a box of each variant
-- in the script builder's live view and baked to a sprite, both through the
-- block shader. Stone variants should read as stone (grey), plank variants
-- as timber (warm), each patterned. Captures land in
-- tests/screenshots/material_render_test/.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local Fake = require("tests.support.fake_input")
local ScriptBuilderScreen = require("src.app.screens.script_builder")
local BuilderCamera = require("src.app.builder_camera")
local Baker = require("src.app.bake.baker")
local Config = require("src.game.config")

local STUDS = Config.builder.studsPerTile
-- Test-only file name in the save directory (docs/memory/e2e-isolate-save-dir.md).
local FILE = "e2e_material.lua"

local function renderFrame(game)
	local w, h = love.graphics.getDimensions()
	local canvas = love.graphics.newCanvas(w, h, { dpiscale = 1 })
	love.graphics.push("all")
	love.graphics.setCanvas(canvas)
	love.graphics.clear(love.graphics.getBackgroundColor())
	game:draw()
	love.graphics.pop()
	return love.graphics.readbackTexture(canvas)
end

-- The builder opened on a 2 x 2 x 1 box made of `material`, `variant`.
local function openBox(material, variant)
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.scriptBuilder = {}
	for k, v in pairs(Config.scriptBuilder) do
		config.scriptBuilder[k] = v
	end
	config.scriptBuilder.testDesign = FILE
	local text = string.format(
		'return group{ id = "root", box{ id = "b", size = { 2, 2, 1 }, material = { name = %q, variant = %q } } }\n',
		material,
		variant
	)
	assert(love.filesystem.write(FILE, text))
	local game = GameHarness.startSession({ width = 20, height = 20 }, { real = true, config = config })
	Fake.tap(game, "b")
	local screen = game.flow.scriptBuilder
	assertEqual(nil, screen.message, screen.message)
	return game, screen, config
end

-- The mean colour of `samples` pixels and how much their brightness varies
-- (standard deviation): a pattern varies, a flat colour doesn't.
local function stats(samples)
	local r, g, b, sum, sumSq = 0, 0, 0, 0, 0
	for _, c in ipairs(samples) do
		r, g, b = r + c[1], g + c[2], b + c[3]
		local l = c[1] + c[2] + c[3]
		sum, sumSq = sum + l, sumSq + l * l
	end
	local n = #samples
	local mean = sum / n
	return r / n, g / n, b / n, math.sqrt(math.max(sumSq / n - mean * mean, 0))
end

-- A grid of pixels over the box's top face in the live view.
local function topSamples(pixels, screen)
	local view = ScriptBuilderScreen.view(screen)
	local out = {}
	for i = 1, 9 do
		for j = 1, 9 do
			local x, y = BuilderCamera.project(view, (0.2 + i * 0.16) * STUDS, (0.2 + j * 0.16) * STUDS, STUDS)
			out[#out + 1] = { pixels:getPixel(math.floor(x), math.floor(y)) }
		end
	end
	return out
end

-- Every opaque pixel of a baked sprite.
local function spriteSamples(image)
	local pixels = love.graphics.readbackTexture(image)
	local out = {}
	for x = 0, pixels:getWidth() - 1, 2 do
		for y = 0, pixels:getHeight() - 1, 2 do
			local r, g, b, a = pixels:getPixel(x, y)
			if a == 1 then
				out[#out + 1] = { r, g, b }
			end
		end
	end
	return out
end

-- Whether mean colour (r, g, b) reads as `material`: stone grey, plank
-- warm.
local function reads(material, r, g, b)
	if material == "stone" then
		return math.abs(r - b) < 0.06 and math.abs(r - g) < 0.06
	end
	return r > b + 0.08
end

for _, material in ipairs({ "plank", "stone" }) do
	for _, variant in ipairs(Config.materials[material].variants) do
		test(material .. " " .. variant .. " reads as " .. material .. ", patterned, live and baked", function()
			local game, screen, config = openBox(material, variant)
			local pixels = renderFrame(game)
			Capture.capture(material .. "_" .. variant)
			local r, g, b, spread = stats(topSamples(pixels, screen))
			assertTrue(reads(material, r, g, b), string.format("live top %.2f %.2f %.2f doesn't read as %s", r, g, b, material))
			assertTrue(spread > 0.03, string.format("live top is flat (spread %.3f)", spread))

			local bp = screen.blueprint
			local sprite = Baker.bakeMesh(bp.mesh, bp.width, bp.depth, "N", config, 2)
			Capture.captureTexture(material .. "_" .. variant .. "_baked", sprite.image)
			r, g, b, spread = stats(spriteSamples(sprite.image))
			assertTrue(reads(material, r, g, b), string.format("baked %.2f %.2f %.2f doesn't read as %s", r, g, b, material))
			assertTrue(spread > 0.03, string.format("baked sprite is flat (spread %.3f)", spread))
			love.filesystem.remove(FILE)
		end)
	end
end

test("the material panel draws under its top bar slot", function()
	local game, screen = openBox("stone", "brick")
	Fake.tap(game, "5")
	local rows = assert(ScriptBuilderScreen.materialPanel(screen))
	local pixels = renderFrame(game)
	Capture.capture("material_panel")
	local last = rows[#rows]
	local r, g, b = pixels:getPixel(last.x + 4, last.y + 2)
	assertTrue(r < 0.2 and g < 0.2 and b < 0.2, "expected the panel's dark background")
	love.filesystem.remove(FILE)
end)
