-- Boots a session the same way src/app/main.lua does, but from a literal
-- world table -- never a file path. Works under plain LuaJIT with no `love`
-- global, because src/game has none (docs/ARCHITECTURE.md "Layers").
-- game:draw() reaches into src/app/render, which uses love.*; only the e2e
-- tier, with a real `love`, calls it.
local Session = require("src.game.session")
local Config = require("src.game.config")
local Input = require("src.app.input")
local Camera = require("src.app.camera")
local Screen = require("src.app.screen")
local WorldRender = require("src.app.render.world")
local CharacterRender = require("src.app.render.character")

local GameHarness = {}

local DEFAULT_SEED = 1

-- opts.config overrides the tuning table (defaults to src/game/config.lua).
-- opts.seed fixes the session seed (defaults to DEFAULT_SEED, so runs are
-- reproducible).
-- opts.real = true announces the game to the e2e runner via
-- _G.E2E_ON_GAME_STARTED, so love.draw and Capture have something to render.
function GameHarness.startSession(world, opts)
	opts = opts or {}

	local ctx = Session.new(world, opts.config or Config, opts.seed or DEFAULT_SEED)
	local player = ctx.pools.characters[1]
	local camera = Camera.new(player.x, player.y)

	local game = { ctx = ctx, camera = camera }

	-- Same order as src/app/main.lua's fixed step: read devices, step, follow.
	function game:update(dt)
		-- With no `love` global (plain integration tests) intents are set
		-- directly on ctx.intents instead.
		if love then
			Input.updateIntents(ctx)
		end
		Session.advance(ctx, dt)
		Camera.follow(camera, player.x, player.y)
	end

	function game:draw()
		Camera.attach(camera, Screen.dimensions())
		WorldRender.draw(ctx)
		CharacterRender.draw(ctx)
		Camera.detach()
	end

	if opts.real and _G.E2E_ON_GAME_STARTED then
		love.graphics.setBackgroundColor(Screen.BACKGROUND)
		_G.E2E_ON_GAME_STARTED(game)
	end

	return game
end

return GameHarness
