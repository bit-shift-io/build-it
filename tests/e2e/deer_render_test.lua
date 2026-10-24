-- Deer under real LÖVE 12: a new world has deer, the camera over a herd
-- draws them (baking the deer atlas on the way), and they wander. Uses its
-- own save file, designs dir and prop cache, cleared first. Captures land in
-- tests/screenshots/deer_render_test/.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local FrameStepper = require("tests.support.frame_stepper")
local Config = require("src.game.config")
local Registry = require("src.game.props.registry")
local Character = require("src.game.props.character")
local PropCache = require("src.app.bake.prop_cache")

local function testConfig()
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.designs = { dir = "e2e_deer_designs", prefabDir = "e2e_deer_prefabs" }
	config.save = { file = "e2e_deer_world.save", seed = Config.save.seed }
	config.props = {}
	for k, v in pairs(Config.props) do
		config.props[k] = v
	end
	config.props.cacheDir = "e2e_deer_props"
	return config
end

local function clear(config)
	for _, dir in ipairs({ config.designs.dir, config.designs.prefabDir, config.props.cacheDir }) do
		for _, name in ipairs(love.filesystem.getDirectoryItems(dir)) do
			love.filesystem.remove(dir .. "/" .. name)
		end
	end
	love.filesystem.remove(config.save.file)
end

test("a new world has deer; the camera beside a herd draws them wandering", function()
	local config = testConfig()
	clear(config)
	local game = GameHarness.launch({ real = true, config = config })
	FrameStepper.step(game, 1)
	game:keypressed("return")
	FrameStepper.step(game, 2)

	local animals = game.ctx.pools.animals
	assertTrue(#animals > 0, "expected deer in a new world")
	local deer = animals[1]
	-- The camera follows the player: stand it beside the deer.
	local player = game.ctx.pools.characters[1]
	player.x, player.y = deer.x - Config.tileSize, deer.y
	local x, y = deer.x, deer.y
	FrameStepper.step(game, 2)
	Capture.capture("deer_in_view")
	FrameStepper.step(game, 60 * 12)
	assertTrue(deer.x ~= x or deer.y ~= y, "expected the deer to wander")
	Capture.capture("deer_later")
	clear(config)
end)

-- A sprite's own pixels as a string.
local function pixelsOf(sprite)
	local _, _, qw, qh = sprite.quad:getViewport()
	local own = love.graphics.newCanvas(qw, qh, { dpiscale = 1 })
	love.graphics.push("all")
	love.graphics.origin()
	love.graphics.setCanvas(own)
	love.graphics.clear(0, 0, 0, 0)
	love.graphics.setBlendMode("replace", "premultiplied")
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.draw(sprite.image, sprite.quad, 0, 0)
	love.graphics.pop()
	local data = love.graphics.readbackTexture(own)
	own:release()
	return data:getString()
end

test("in iso the 8 deer facings bake 8 different sprites on their 1x1 tile", function()
	local config = testConfig()
	config.props.cacheDir = "e2e_deer_iso"
	clear(config)
	local cache = PropCache.new({ deer = Registry.DEER }, config)
	local seen = {}
	for dir = 1, #Character.DIRECTIONS do
		local sprite = PropCache.sprite(cache, "deer", dir, Character.IDLE, 4, "iso")
		assertEqual(1, sprite.width)
		assertEqual(1, sprite.depth)
		local pixels = pixelsOf(sprite)
		for other, p in pairs(seen) do
			assertTrue(p ~= pixels, Character.DIRECTIONS[dir].name .. " and " .. Character.DIRECTIONS[other].name .. " look the same")
		end
		seen[dir] = pixels
	end
	clear(config)
end)
