-- Boots a session the same way src/app/main.lua does, but from a literal
-- world table -- never a file path -- and routes every LÖVE-style callback
-- through the same src/app/flow.lua the app uses. Needs a `love` global
-- (the integration tier's love_mock, or real LÖVE under e2e) for input.
-- game:draw() reaches into src/app/render, which uses love.graphics; only
-- the e2e tier, with a real `love`, calls it.
local Session = require("src.game.session")
local Config = require("src.game.config")
local Flow = require("src.app.flow")
local Screen = require("src.app.screen")

local GameHarness = {}

local DEFAULT_SEED = 1

-- opts.config overrides the tuning table (defaults to src/game/config.lua).
-- opts.seed fixes the session seed (defaults to DEFAULT_SEED, so runs are
-- reproducible).
-- opts.real = true announces the game to the e2e runner via
-- _G.E2E_ON_GAME_STARTED, so love.draw and Capture have something to render.
function GameHarness.startSession(world, opts)
	opts = opts or {}

	local config = opts.config or Config
	local ctx = Session.new(world, config, opts.seed or DEFAULT_SEED)
	local flow = Flow.new(ctx, config)

	local game = { ctx = ctx, flow = flow, camera = flow.world.camera }

	-- One fixed step, as src/app/main.lua runs per accumulated 1/60 s.
	function game:update(dt)
		Flow.update(flow, dt)
	end

	function game:draw()
		Flow.draw(flow)
	end

	function game:keypressed(key)
		Flow.keypressed(flow, key)
	end

	function game:mousepressed(x, y, button)
		Flow.mousepressed(flow, x, y, button)
	end

	function game:mousereleased(x, y, button)
		Flow.mousereleased(flow, x, y, button)
	end

	function game:mousemoved(x, y, dx, dy)
		Flow.mousemoved(flow, x, y, dx, dy)
	end

	function game:wheelmoved(x, y)
		Flow.wheelmoved(flow, x, y)
	end

	if opts.real and _G.E2E_ON_GAME_STARTED then
		love.graphics.setBackgroundColor(Screen.BACKGROUND)
		_G.E2E_ON_GAME_STARTED(game)
	end

	return game
end

return GameHarness
