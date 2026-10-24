-- Blueprints (docs/CONTEXT.md "Blueprint", ADR 0007): what the simulation
-- reads, compiled from a design script (src/game/buildings/compile.lua):
-- footprint, port tiles, function brick tiles, cost, traits, and a content
-- hash.
local Config = require("src.game.config")
local Blueprint = require("src.game.buildings.blueprint")
local Starter = require("src.game.designs.starter")
local Builtins = require("tests.support.builtins")
local Designs = require("tests.support.designs")
local Site = require("src.game.buildings.site")

-- A 3x2 sawmill: a sawbench on tile (2, 1), an input port on the west
-- edge, an output port on the east edge.
local MILL = Designs.floor(3, 2,
	Designs.ability("sawbench", 2.5, 1.5),
	Designs.port("input", 0.125, 1.375),
	Designs.port("output", 2.875, 0.625))

local function starter()
	return Starter.blueprint(Builtins, Config)
end

local function mill()
	return Designs.blueprint(MILL)
end

test("the starter blueprint is 3 x 2 tiles", function()
	local bp = starter()
	assertEqual(3, bp.width)
	assertEqual(2, bp.depth)
end)

local Placement = require("src.game.buildings.placement")

local function assertPort(port, kind, side, x, y)
	assertEqual(kind, port.kind)
	assertEqual(side, port.side, kind .. " side")
	assertEqual(x, port.x, kind .. " x")
	assertEqual(y, port.y, kind .. " y")
end

test("a rotated sawmill blueprint keeps its footprint and port tiles", function()
	local bp = mill()
	local w, d = Placement.footprint(bp, "E")
	assertEqual(2, w)
	assertEqual(3, d)
	local ports = Placement.ports(bp, "E", 10, 10)
	assertEqual(2, #ports)
	assertPort(ports[1], "input", "N", 10, 9)
	assertPort(ports[2], "output", "S", 11, 13)
end)

test("the starter blueprint keeps its port tiles", function()
	local ports = Placement.ports(starter(), "N", 10, 10)
	assertEqual(2, #ports)
	assertPort(ports[1], "input", "S", 11, 12)
	assertPort(ports[2], "output", "S", 12, 12)
end)

local Session = require("src.game.session")
local World = require("src.game.world")
local Storage = require("src.game.components.storage")

local function newCtx()
	return Session.new(World.new(30, 30), Config, 1)
end

test("a rotated sawmill's operator tile comes from its blueprint, turned by facing", function()
	local b = Placement.build(newCtx(), { blueprint = mill(), facing = "E", tileX = 10, tileY = 10 })
	assertEqual(1, #b.functionBricks)
	assertEqual("sawbench", b.functionBricks[1].ability)
	assertEqual(10, b.functionBricks[1].tileX)
	assertEqual(12, b.functionBricks[1].tileY)
	assertEqual(Storage.size(Config.production.bufferSize, mill().traits, Config), b.ports[1].buffer.capacity)
end)

test("the starter building's depot tile and storage come from its blueprint", function()
	local b = Placement.build(newCtx(), { blueprint = starter(), facing = "N", tileX = 10, tileY = 10 })
	assertEqual("depot", b.functionBricks[1].ability)
	assertEqual(10, b.functionBricks[1].tileX)
	assertEqual(11, b.functionBricks[1].tileY)
	assertEqual(264, b.storage.capacity)
end)

local Mesh = require("src.game.geometry.mesh")

test("a blueprint's mesh is triangles in tiles over its footprint", function()
	local bp = mill()
	assertTrue(#bp.mesh > 0 and #bp.mesh % 3 == 0, "expected whole triangles")
	local b = Mesh.bounds(bp.mesh)
	assertNear(0, b.minX)
	assertNear(0, b.minY)
	assertTrue(b.maxX <= 3 and b.maxY <= 2, "inside the 3 x 2 footprint")
end)

local function deepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in pairs(t) do
		out[k] = deepCopy(v)
	end
	return out
end

test("the content hash follows the content, not the table", function()
	assertEqual("string", type(mill().hash))
	assertEqual(mill().hash, Blueprint.hash(deepCopy(mill())), "equal content, other tables")
	assertFalse(mill().hash == starter().hash)
	local moved = deepCopy(mill())
	moved.mesh[4].r = 0.5
	assertFalse(mill().hash == Blueprint.hash(moved), "a repaint changes the hash")
end)

test("a placed building and site hold the blueprint they were placed with", function()
	local ctx = Session.newGame(World.new(60, 60), Config, 1, Builtins)
	local b = ctx.pools.buildings[1]
	assertEqual(starter().hash, b.blueprint.hash)
	assertEqual(Starter.NAME, b.design)

	local site = assert(Placement.place(ctx, Designs.request(MILL, "E", 5, 5, "Mill")))
	assertEqual(mill(), site.blueprint)
	assertEqual("Mill", site.design)
	for item, n in pairs(mill().cost) do
		assertEqual(n, site.cost[item], item)
	end
	local built = Placement.build(ctx, Site.request(site))
	assertEqual(site.blueprint, built.blueprint)
	assertEqual(7, built.functionBricks[1].tileY, "the sawbench sits on footprint tile (0, 2) facing E")
end)
