-- Needs (src/game/components/needs.lua): rising meters, thresholds timed
-- from config, collapse.
local Needs = require("src.game.components.needs")
local Config = require("src.game.config")

local cfg = Config.needs

-- Seconds of ticking (1 s steps) until `done(needs)` holds; nil past 2000.
local function secondsUntil(needs, isPlayer, done)
	for t = 1, 2000 do
		Needs.tick(needs, 1, cfg, isPlayer)
		if done(needs) then
			return t
		end
	end
end

test("a new needs record is healthy, fed and rested", function()
	local n = Needs.new()
	assertEqual(1, n.health)
	assertEqual(0, n.hunger)
	assertEqual(0, n.tiredness)
	assertEqual(false, Needs.collapsed(n))
	assertEqual(false, Needs.inNeed(n, cfg))
end)

test("a meal falls due in about 3 minutes", function()
	local t = secondsUntil(Needs.new(), false, function(n) return Needs.inNeed(n, cfg) end)
	assert(t >= 170 and t <= 190, "meal due after " .. tostring(t))
end)

test("sleep falls due in about 8 minutes", function()
	local n = Needs.new()
	n.hunger = -100 -- never hungry
	local t = secondsUntil(n, false, function(x) x.hunger = 0 return Needs.inNeed(x, cfg) end)
	assert(t >= 470 and t <= 490, "sleep due after " .. tostring(t))
end)

test("the player's tiredness stays at 0", function()
	local n = Needs.new()
	for _ = 1, 1000 do
		Needs.tick(n, 1, cfg, true)
	end
	assertEqual(0, n.tiredness)
	assert(n.hunger > 0)
end)

test("starving reaches collapse in about 2 minutes after full hunger", function()
	local n = Needs.new()
	n.hunger = 1
	local t = secondsUntil(n, false, Needs.collapsed)
	assert(t >= 115 and t <= 125, "collapsed after " .. tostring(t))
end)

test("health regenerates once hunger is below the starving threshold", function()
	local n = Needs.new()
	n.health = 0.2
	n.hunger = 0.5
	Needs.tick(n, 10, { hungerRate = 0, tirednessRate = 0, starvingAt = 0.9, drainRate = 0.1, regenRate = 0.01 })
	assert(math.abs(n.health - 0.3) < 1e-9)
end)

test("health holds between the starving threshold and full hunger", function()
	local n = Needs.new()
	n.health = 0.5
	n.hunger = 0.95
	Needs.tick(n, 10, { hungerRate = 0, tirednessRate = 0, starvingAt = 0.9, drainRate = 0.1, regenRate = 0.01 })
	assertEqual(0.5, n.health)
end)
