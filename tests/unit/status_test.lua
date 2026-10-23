-- The hover card's text (src/game/components/status.lua) and the names
-- sessions hand out.
local Session = require("src.game.session")
local Builtins = require("tests.support.builtins")
local World = require("src.game.world")
local Config = require("src.game.config")
local Status = require("src.game.components.status")
local Load = require("src.game.components.load")

local function villager()
	return Session.newVillager(1, 0, 0, Config)
end

test("an operator reads Operating and its ability", function()
	local v = villager()
	v.job = { kind = "operate", brick = { ability = "saw" } }
	assertEqual("Operating Saw", Status.activity(v))
end)

test("a hauler reads Hauling and the item", function()
	local v = villager()
	v.job = { kind = "haul", item = "plank" }
	assertEqual("Hauling plank", Status.activity(v))
end)

test("a builder reads Building", function()
	local v = villager()
	v.job = { kind = "build" }
	assertEqual("Building", Status.activity(v))
end)

test("a villager with no job reads Idle", function()
	assertEqual("Idle", Status.activity(villager()))
end)

test("the card lists name, activity, load and experience per role", function()
	local v = villager()
	v.name = "Ada"
	v.load.item, v.load.count = "log", 2
	v.xp = { saw = 3, haul = 5 }
	local lines = Status.lines(v)
	assertEqual("Ada", lines[1])
	assertEqual("Idle", lines[2])
	assertEqual("Load: 2 log", lines[3])
	assertEqual("haul: 5", lines[4])
	assertEqual("saw: 3", lines[5])
end)

test("an empty load and no experience read plainly", function()
	local v = villager()
	v.name = "Bo"
	local lines = Status.lines(v)
	assertEqual("Load: empty", lines[3])
	assertEqual("No experience", lines[4])
end)

test("the player's card is its name and activity", function()
	local ctx = Session.new(World.new(20, 20), Config, 1)
	local p = ctx.pools.characters[1]
	local lines = Status.lines(p)
	assertEqual(p.name, lines[1])
	assertEqual("Idle", lines[2])
	assertEqual(2, #lines)
end)

test("the same seed gives the same names, from the config list", function()
	local function names(seed)
		local ctx = Session.new(World.new(20, 20), Config, seed)
		return ctx.pools.characters[1].name
	end
	assertEqual(names(5), names(5))
	local found = false
	for _, n in ipairs(Config.names) do
		found = found or n == names(5)
	end
	assertTrue(found)
end)

test("newGame names every villager, the same way for the same seed", function()
	local WorldGen = require("src.game.world_gen")
	local function names(seed)
		local ctx = Session.newGame(WorldGen.generate(Config, seed), Config, seed, Builtins)
		local out = {}
		for _, v in ipairs(ctx.pools.villagers) do
			assertTrue(v.name ~= nil)
			out[#out + 1] = v.name
		end
		return table.concat(out, ",")
	end
	assertEqual(names(3), names(3))
end)

test("a collapsed villager reads Collapsed whatever its job", function()
	local v = villager()
	v.job = { kind = "haul", item = "plank" }
	v.needs.health = 0
	assertEqual("Collapsed", Status.activity(v))
end)

test("the card's bars are health, hunger and tiredness as fractions", function()
	local v = villager()
	v.needs.health, v.needs.hunger, v.needs.tiredness = 0.5, 0.25, 0.75
	local bars = Status.bars(v)
	assertEqual(3, #bars)
	assertEqual("Health", bars[1].label)
	assertEqual(0.5, bars[1].value)
	assertEqual("Hunger", bars[2].label)
	assertEqual(0.25, bars[2].value)
	assertEqual("Tiredness", bars[3].label)
	assertEqual(0.75, bars[3].value)
end)

test("the player's card has no tiredness bar", function()
	local ctx = Session.new(World.new(20, 10), Config, 1)
	local bars = Status.bars(ctx.pools.characters[1])
	assertEqual(2, #bars)
	assertEqual("Hunger", bars[2].label)
end)

test("an eater reads Eating", function()
	local v = villager()
	v.job = { kind = "eat" }
	assertEqual("Eating", Status.activity(v))
end)

test("the hunger warning reads only while it applies", function()
	local needs = { hunger = 0 }
	assertEqual(nil, Status.hunger(needs, Config.needs))
	needs.hunger = Config.needs.hungryAt - 0.01
	assertEqual(nil, Status.hunger(needs, Config.needs))
	needs.hunger = Config.needs.hungryAt
	assertEqual("Hungry", Status.hunger(needs, Config.needs))
	needs.hunger = Config.needs.starvingAt
	assertEqual("Starving", Status.hunger(needs, Config.needs))
end)

test("the card appends aura lines after experience; none for a zero aura", function()
	local v = villager()
	v.xp = { saw = 3 }
	local lines = Status.lines(v, { walkSpeed = 0.05, harvestRate = 0 })
	assertEqual("saw: 3", lines[4])
	assertEqual("Walk speed +5.0%", lines[5])
	assertEqual(5, #lines)
	assertEqual(4, #Status.lines(v, { walkSpeed = 0, harvestRate = 0 }))
	assertEqual(4, #Status.lines(v))
end)
