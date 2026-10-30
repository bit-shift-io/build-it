-- The building card's lines (src/game/components/building_status.lua) for a
-- finished building and a construction site.
local Session = require("src.game.session")
local World = require("src.game.world")
local Config = require("src.game.config")
local Placement = require("src.game.buildings.placement")
local Storage = require("src.game.components.storage")
local BuildingStatus = require("src.game.components.building_status")
local Designs = require("tests.support.designs")

local TEXT = Designs.floor(2, 1, Designs.ability("sawbench", 0.5, 0.25), Designs.storage(8, 1.5, 0.5), Designs.port("input", 0.25, 1))

local STORE = Designs.floor(1, 1, Designs.ability("depot", 0.25, 0.25), Designs.storage(8, 0.75, 0.25), Designs.port("input", 0.25, 1), Designs.port("output", 0.75, 1))

local function setup()
	local ctx = Session.new(World.new(20, 20), Config, 1)
	return ctx
end

local function texts(lines)
	local out = {}
	for _, l in ipairs(lines) do
		out[#out + 1] = type(l) == "table" and l.text or l
	end
	return out
end

local function has(lines, prefix)
	for _, t in ipairs(texts(lines)) do
		if t:sub(1, #prefix) == prefix then
			return t
		end
	end
end

test("a building's card names the design, bricks with operator, traits and contents", function()
	local ctx = setup()
	local b = Placement.build(ctx, Designs.request(TEXT, "N", 8, 8, "Mill"))
	Storage.add(b.storage, "plank")
	Storage.add(b.ports[1].buffer, "log")
	Storage.add(b.ports[1].buffer, "log")
	local lines = BuildingStatus.lines(b, Config)
	assertEqual("Mill", lines[1])
	assertTrue(has(lines, "Sawbench") ~= nil, "ability line")
	assertTrue(has(lines, "Sawbench").find(has(lines, "Sawbench"), "no operator", 1, true) ~= nil, "no operator")
	local brick = lines[2]
	assertEqual("table", type(brick))
	assertEqual(Config.reachColors.default, brick.swatch)
	assertTrue(has(lines, "Productivity") ~= nil)
	assertTrue(has(lines, "Capacity") ~= nil)
	assertTrue(has(lines, "Health") ~= nil)
	assertEqual("Storage: 1 plank", has(lines, "Storage"))
	assertEqual("Input: 2 log", has(lines, "Input"))
end)

test("an operator's name replaces 'no operator'", function()
	local ctx = setup()
	local b = Placement.build(ctx, Designs.request(TEXT, "N", 8, 8, "Mill"))
	b.functionBricks[1].operator = { villager = { name = "Ada" } }
	local line = has(BuildingStatus.lines(b, Config), "Sawbench")
	assertTrue(line:find("Ada", 1, true) ~= nil, line)
end)

test("a site's card shows Construction site and delivered/needed per material", function()
	local ctx = setup()
	local store = Placement.build(ctx, Designs.request(STORE, "N", 2, 2, "Store"))
	store.storage.capacity = 1000
	for item, n in pairs(Designs.blueprint(TEXT).cost) do
		for _ = 1, n do
			Storage.add(store.storage, item)
		end
	end
	local site = assert(Placement.place(ctx, Designs.request(TEXT, "N", 8, 8, "Mill")))
	local item, need = next(site.cost)
	Storage.add(site.delivered, item)
	local lines = BuildingStatus.lines(site, Config)
	assertEqual("Mill", lines[1])
	assertEqual("Construction site", lines[2])
	assertEqual(item .. ": 1/" .. need, has(lines, item))
	assertTrue(has(lines, "Sawbench") ~= nil, "brick line")
	assertEqual(nil, has(lines, "Storage"))
end)

test("an aura adds a swatch line and its lines", function()
	local ctx = setup()
	local b = Placement.build(ctx, Designs.request(TEXT, "N", 8, 8, "Mill"))
	b.aura = { walkSpeed = 0.05, harvestRate = 0 }
	b.blueprint.auras.walkSpeed = 0.05
	local lines = BuildingStatus.lines(b, Config)
	local line
	for _, l in ipairs(lines) do
		if type(l) == "table" and l.swatch == Config.reachColors.aura then
			line = l
		end
	end
	assertTrue(line ~= nil, "aura swatch row")
	assertTrue(has(lines, "Walk speed") ~= nil, "aura line")
end)
