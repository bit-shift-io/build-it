-- LÖVE callbacks and the fixed-timestep accumulator. This is the only module
-- main.lua requires; every other app module hangs off it. No game or core
-- module may require anything from here (docs/ARCHITECTURE.md "Layers").
-- Every callback goes to src/app/flow.lua, which owns the screens.
local Session = require("src.game.session")
local WorldGen = require("src.game.world_gen")
local Config = require("src.game.config")
local Flow = require("src.app.flow")
local Screen = require("src.app.screen")

-- Fixed timestep of 1/60 s (docs/ARCHITECTURE.md "Rules"): the simulation
-- must be deterministic for a given seed and input sequence, which a
-- variable dt cannot guarantee.
local FIXED_DT = 1 / 60
local SEED = 1

local App = {
	flow = nil,
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
	App.flow = Flow.new(Session.new(WorldGen.generate(Config, SEED), Config, SEED), Config)
end

function love.keypressed(key)
	Flow.keypressed(App.flow, key)
end

function love.textinput(text)
	Flow.textinput(App.flow, text)
end

function love.mousepressed(x, y, button)
	Flow.mousepressed(App.flow, x, y, button)
end

function love.mousereleased(x, y, button)
	Flow.mousereleased(App.flow, x, y, button)
end

function love.mousemoved(x, y, dx, dy)
	Flow.mousemoved(App.flow, x, y, dx, dy)
end

function love.wheelmoved(x, y)
	Flow.wheelmoved(App.flow, x, y)
end

function love.update(dt)
	App.accumulator = App.accumulator + dt
	while App.accumulator >= FIXED_DT do
		Flow.update(App.flow, FIXED_DT)
		App.accumulator = App.accumulator - FIXED_DT
	end
end

function love.draw()
	Flow.draw(App.flow)
end

return App
