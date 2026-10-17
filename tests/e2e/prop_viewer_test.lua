-- The dev prop viewer under real LÖVE 12: every variant x stage of a kind in
-- one grid. Captures land in tests/screenshots/prop_viewer_test/.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local Config = require("src.game.config")
local Registry = require("src.game.props.registry")
local Viewer = require("tools.prop_viewer.main")

-- Capture.capture renders the game, not the viewer, so draw it to a canvas.
local function captureViewer(viewer, name)
	local canvas = love.graphics.newCanvas(1280, 720, { dpiscale = 1 })
	love.graphics.push("all")
	love.graphics.origin()
	love.graphics.setCanvas(canvas)
	Viewer.draw(viewer)
	love.graphics.pop()
	Capture.captureTexture(name, canvas)
end

GameHarness.startSession({ width = 20, height = 20 }, { real = true })

test("the tree grid shows variants x stages sprites and R rebakes", function()
	local viewer = Viewer.new(Config)
	assertEqual("tree", Viewer.kind(viewer))
	local def = Registry.KINDS.tree
	assertEqual(Registry.variants(def, Config) * def.stages, Viewer.spriteCount(viewer))
	captureViewer(viewer, "tree_grid")

	Viewer.keypressed(viewer, "r")
	assertEqual(Registry.variants(def, Config) * def.stages, Viewer.spriteCount(viewer))

	Viewer.keypressed(viewer, "right")
	assertEqual("rock", Viewer.kind(viewer))
	captureViewer(viewer, "rock_grid")
	Viewer.keypressed(viewer, "right")
	assertEqual("bush", Viewer.kind(viewer))
	assertEqual(Registry.variants(Registry.KINDS.bush, Config) * Registry.KINDS.bush.stages, Viewer.spriteCount(viewer))
	captureViewer(viewer, "bush_grid")
	Viewer.keypressed(viewer, "right")
	assertEqual("character", Viewer.kind(viewer))
	assertEqual(8 * 5, Viewer.spriteCount(viewer))
	captureViewer(viewer, "character_grid")
end)
