-- LÖVE callbacks and the fixed-timestep accumulator. This is the only module
-- main.lua requires; every other app module hangs off it. No game or core
-- module may require anything from here (docs/ARCHITECTURE.md "Layers").
local Session = require("src.game.session")
local WorldGen = require("src.game.world_gen")
local Config = require("src.game.config")
local Input = require("src.app.input")
local Camera = require("src.app.camera")
local Screen = require("src.app.screen")
local WorldRender = require("src.app.render.world")
local CharacterRender = require("src.app.render.character")

-- Fixed timestep of 1/60 s (docs/ARCHITECTURE.md "Rules"): the simulation
-- must be deterministic for a given seed and input sequence, which a
-- variable dt cannot guarantee.
local FIXED_DT = 1 / 60
local SEED = 1

local App = {
	ctx = nil,
	camera = nil,
	player = nil,
	accumulator = 0,
}

-- e2e=<path/to/scenario_test.lua> hands control to the e2e runner instead of
-- constructing the normal App (see tests/e2e/run.lua).
local function findE2ETestFile(args)
	for _, a in ipairs(args or {}) do
		local path = a:match("^e2e=(.+)$")
		if path then
			return path
		end
	end
	return nil
end

function love.load(args)
	local e2eTestFile = findE2ETestFile(args)
	if e2eTestFile then
		-- requiring tests.e2e.run defines its own love.update/love.draw/
		-- love.quit, replacing the ones below for the rest of this process.
		local E2ERunner = require("tests.e2e.run")
		E2ERunner.start(e2eTestFile, args)
		return
	end

	love.graphics.setBackgroundColor(Screen.BACKGROUND)
	App.ctx = Session.new(WorldGen.generate(Config, SEED), Config, SEED)
	App.player = App.ctx.pools.characters[1]
	App.camera = Camera.new(App.player.x, App.player.y)
end

function love.wheelmoved(_, y)
	Camera.zoomBy(App.camera, y, Config.camera)
end

function love.update(dt)
	App.accumulator = App.accumulator + dt
	while App.accumulator >= FIXED_DT do
		Input.updateIntents(App.ctx)
		Session.advance(App.ctx, FIXED_DT)
		App.accumulator = App.accumulator - FIXED_DT
	end
	Camera.follow(App.camera, App.player.x, App.player.y)
end

function love.draw()
	Camera.attach(App.camera, Screen.dimensions())
	WorldRender.draw(App.ctx, App.camera.zoom)
	CharacterRender.draw(App.ctx)
	Camera.detach()
end

return App
