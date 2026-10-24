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
local Placement = require("src.game.buildings.placement")
local Storage = require("src.game.components.storage")
local Site = require("src.game.buildings.site")
local Designs = require("tests.support.designs")

local GameHarness = {}

local DEFAULT_SEED = 1

-- `config` (default: the tuning table) with a test-only settings file unless
-- it sets its own, so a session never reads or writes the player's real
-- settings (docs/memory/e2e-isolate-save-dir.md).
local function testConfig(config)
	config = config or Config
	if config.settings ~= Config.settings then
		return config
	end
	local copy = {}
	for k, v in pairs(config) do
		copy[k] = v
	end
	copy.settings = { file = "test_settings.cfg" }
	return copy
end

-- opts.config overrides the tuning table (defaults to src/game/config.lua).
-- opts.seed fixes the session seed (defaults to DEFAULT_SEED, so runs are
-- reproducible).
-- opts.storage = { [item] = n } adds a storage facility holding those
-- items (GameHarness.addStorage), so placement can pay.
-- opts.real = true announces the game to the e2e runner via
-- _G.E2E_ON_GAME_STARTED, so love.draw and Capture have something to render.
function GameHarness.startSession(world, opts)
	opts = opts or {}

	local config = testConfig(opts.config)
	local ctx = Session.new(world, config, opts.seed or DEFAULT_SEED)
	if opts.storage then
		GameHarness.addStorage(ctx, opts.storage)
	end
	return GameHarness.wrap(Flow.new(ctx, config), opts)
end

-- A 1x1-tile storage facility: a depot, storage, and input and output
-- ports on its north edge, so they face into the world from the
-- south-east corner tile.
local STORE = Designs.floor(1, 1,
	Designs.port("input", 0.25, 0),
	Designs.port("output", 0.75, 0),
	Designs.ability("depot", 0.25, 0.5),
	Designs.storage(8, 0.75, 0.5))

-- Builds STORE free on the world's south-east corner tile (or tile x, y),
-- holding `items` ({ [item] = n }) however many its bricks would fit.
-- Returns the building, the first in ctx.pools.buildings when added first.
function GameHarness.addStorage(ctx, items, x, y)
	local b = Placement.build(ctx, Designs.request(STORE, "N", x or ctx.world.width - 1, y or ctx.world.height - 1, "test_storage", ctx.config))
	local total = 0
	for _, n in pairs(items) do
		total = total + n
	end
	b.storage.capacity = math.max(b.storage.capacity, total)
	for item, n in pairs(items) do
		for _ = 1, n do
			Storage.add(b.storage, item)
		end
	end
	return b
end

-- A shortcut for tests about what a building does, not how it is built:
-- every construction site gets its claimed cost moved out of storage and
-- delivered, and its build finished, then the game steps until each one is
-- a building. Villager hauling and building is tested on its own
-- (tests/unit/site_test.lua, tests/integration/place_building_test.lua).
function GameHarness.completeSites(game)
	local ctx = game.ctx
	for _, site in ipairs(ctx.pools.sites) do
		for _, claim in ipairs(site.claims) do
			for _ = 1, claim.count do
				Storage.remove(claim.store, claim.item)
				-- past Storage.add: a haul on its way holds room
				site.delivered.counts[claim.item] = (site.delivered.counts[claim.item] or 0) + 1
			end
			Storage.unclaim(claim.store, claim.item, claim.count)
			claim.count = 0
		end
		site.claims = {}
		site.progress = Site.buildTime(site, ctx.config)
	end
	for _ = 1, 10 do
		if #ctx.pools.sites == 0 then
			return
		end
		game:update(1 / 60)
	end
	error("the sites did not turn into buildings")
end

-- Boots the app as src/app/main.lua does: on the title screen (Continue /
-- New game) over love.filesystem's save directory. game.ctx and
-- game.camera follow the session once one starts. opts.config, opts.real
-- as for startSession.
function GameHarness.launch(opts)
	opts = opts or {}
	return GameHarness.wrap(Flow.launch(testConfig(opts.config)), opts)
end

-- The game object over `flow`: callbacks routed through Flow.
function GameHarness.wrap(flow, opts)
	local game = setmetatable({ flow = flow }, {
		__index = function(_, key)
			if key == "ctx" then
				return flow.ctx
			elseif key == "camera" then
				return flow.world and flow.world.camera
			end
		end,
	})

	function game:quit()
		Flow.quit(flow)
	end

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

	-- Dropped while text input is off, as LÖVE does: no textinput event.
	function game:textinput(text)
		if not love.keyboard.hasTextInput() then
			return
		end
		Flow.textinput(flow, text)
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
