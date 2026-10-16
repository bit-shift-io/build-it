-- The voxel character under real LÖVE 12: its 8 directions baked into the
-- prop cache, a filmstrip of walk frame 2, and the character walking and
-- standing in the world. Captures land in tests/screenshots/character_render_test/.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local Registry = require("src.game.props.registry")
local Character = require("src.game.props.character")
local PropCache = require("src.app.bake.prop_cache")
local CharacterRender = require("src.app.render.character")

local function configWithCacheDir(dir)
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.props = { variants = Config.props.variants, seed = Config.props.seed, cacheDir = dir }
	return config
end

local function clearDir(dir)
	for _, name in ipairs(love.filesystem.getDirectoryItems(dir)) do
		love.filesystem.remove(dir .. "/" .. name)
	end
end

local function exists(path)
	return love.filesystem.getInfo(path) ~= nil
end

local function touchAll(cache)
	for dir = 1, #Character.DIRECTIONS do
		for frame = 1, Character.FRAMES do
			local sprite = PropCache.sprite(cache, "character", dir, frame, 1)
			assertTrue(sprite.image ~= nil and sprite.quad ~= nil, "sprite for direction " .. dir .. " frame " .. frame)
		end
	end
end

-- Draws sprites side by side into one canvas, `gap` px apart on a grey
-- backdrop, returning the canvas and each sprite's own pixels as a string.
local function filmstrip(sprites, gap)
	local w, h = gap, 0
	for _, s in ipairs(sprites) do
		w = w + s.frame.width + gap
		h = math.max(h, s.frame.height)
	end
	local canvas = love.graphics.newCanvas(w, h + 2 * gap, { dpiscale = 1 })
	local pixels = {}
	love.graphics.push("all")
	love.graphics.origin()
	love.graphics.setCanvas(canvas)
	love.graphics.clear(0.3, 0.3, 0.3, 1)
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.setBlendMode("alpha", "premultiplied")
	local x = gap
	for i, s in ipairs(sprites) do
		love.graphics.draw(s.image, s.quad, x, gap)
		local _, _, qw, qh = s.quad:getViewport()
		local own = love.graphics.newCanvas(qw, qh, { dpiscale = 1 })
		love.graphics.setCanvas(own)
		love.graphics.clear(0, 0, 0, 0)
		love.graphics.setBlendMode("replace", "premultiplied")
		love.graphics.draw(s.image, s.quad, 0, 0)
		love.graphics.setCanvas(canvas)
		love.graphics.setBlendMode("alpha", "premultiplied")
		pixels[i] = love.graphics.readbackTexture(own):getString()
		own:release()
		x = x + s.frame.width + gap
	end
	love.graphics.pop()
	return canvas, pixels
end

-- Capture needs a live context, which a real session provides.
GameHarness.startSession({ width = 20, height = 20 }, { real = true })

test("the 8 directions of walk frame 2 all bake differently", function()
	local config = configWithCacheDir("e2e_character_strip")
	clearDir(config.props.cacheDir)
	local scale = 4
	local sprites = {}
	for dir = 1, #Character.DIRECTIONS do
		sprites[dir] = CharacterRender.sprite(config, dir, Character.WALK[1], scale)
	end
	local strip, pixels = filmstrip(sprites, 8)
	Capture.captureTexture("walk_frame2_8_directions", strip)
	for a = 1, #pixels do
		for b = a + 1, #pixels do
			assertTrue(pixels[a] ~= pixels[b], Character.DIRECTIONS[a].name .. " and " .. Character.DIRECTIONS[b].name .. " look the same")
		end
	end

	-- Every frame of every direction, one row per direction, for review.
	local rows = {}
	for dir = 1, #Character.DIRECTIONS do
		local row = {}
		for frame = 1, Character.FRAMES do
			row[frame] = CharacterRender.sprite(config, dir, frame, scale)
		end
		local canvas, framePixels = filmstrip(row, 8)
		for f = 2, #framePixels do
			assertTrue(framePixels[f] ~= framePixels[f - 1], Character.DIRECTIONS[dir].name .. " frame " .. f .. " repeats the last")
		end
		rows[dir] = canvas
	end
	local sheetW, sheetH = 0, 0
	for _, row in ipairs(rows) do
		sheetW, sheetH = math.max(sheetW, row:getWidth()), sheetH + row:getHeight()
	end
	local sheet = love.graphics.newCanvas(sheetW, sheetH, { dpiscale = 1 })
	love.graphics.push("all")
	love.graphics.origin()
	love.graphics.setCanvas(sheet)
	love.graphics.clear(0.3, 0.3, 0.3, 1)
	love.graphics.setBlendMode("replace", "premultiplied")
	local y = 0
	for _, row in ipairs(rows) do
		love.graphics.draw(row, 0, y)
		y = y + row:getHeight()
	end
	love.graphics.pop()
	Capture.captureTexture("all_directions_all_frames", sheet)
end)

test("character frames cache with the props and rebake when the generator version changes", function()
	local config = configWithCacheDir("e2e_character_cache")
	clearDir(config.props.cacheDir)
	local def = Registry.CHARACTER
	local kinds = { character = def }

	local first = PropCache.new(kinds, config)
	touchAll(first)
	assertEqual("character@1", table.concat(first.baked, ","))
	local path = config.props.cacheDir .. "/character_v" .. def.version .. "_x1.png"
	assertTrue(exists(path), "expected " .. path)

	local second = PropCache.new(kinds, config)
	touchAll(second)
	assertEqual("", table.concat(second.baked, ","), "expected the second launch to bake nothing")

	local bumped = {}
	for k, v in pairs(def) do
		bumped[k] = v
	end
	bumped.version = def.version + 1
	local third = PropCache.new({ character = bumped }, config)
	touchAll(third)
	assertEqual("character@1", table.concat(third.baked, ","))
	assertTrue(exists(config.props.cacheDir .. "/character_v" .. bumped.version .. "_x1.png"), "new atlas cached")
	assertFalse(exists(path), "stale atlas removed")
end)

test("the character faces and animates as it walks, and idles in its last facing", function()
	local config = configWithCacheDir("e2e_character_world")
	clearDir(config.props.cacheDir)
	local game = GameHarness.startSession(World.new(20, 20), { real = true, config = config, seed = 1 })
	local input = Fake.FakeInput.new()
	local c = game.ctx.pools.characters[1]
	game.camera.zoom = 3

	Capture.capture("idle_facing_south")

	input:press("d")
	Fake.holdFor(game, input, "s", 0.2)
	input:release("d")
	assertEqual("SE", Character.DIRECTIONS[c.animator.facing].name)
	assertTrue(c.animator.frame ~= Character.IDLE, "walking shows a walk frame")
	Capture.capture("walking_south_east")

	Fake.holdFor(game, input, "a", 0.3)
	assertEqual("W", Character.DIRECTIONS[c.animator.facing].name)
	Capture.capture("walking_west")

	game:update(1 / 60)
	assertEqual(Character.IDLE, c.animator.frame)
	assertEqual("W", Character.DIRECTIONS[c.animator.facing].name)
	Capture.capture("idle_facing_west")
end)
