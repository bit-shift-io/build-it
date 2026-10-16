-- Placing a building (docs/CONTEXT.md "Building", "Footprint", "Port"):
-- footprint and port tiles per facing, every reason a placement is refused,
-- and the cost paid once.
local Placement = require("src.game.buildings.placement")
local Config = require("src.game.config")

local CFG = Config.builder

local function brick(x, y, z, port)
	return { x = x, y = y, z = z, width = 1, depth = 1, shape = "1x1", rotation = 0, material = "plank", paint = 1, port = port }
end

-- A 3x2 tile design (12x8 studs), asymmetric: an input port on the west
-- edge in tile (0, 1), an output port on the north edge in tile (2, 0).
-- A port brick above ground and one off the edge are not ports.
local function asymmetric()
	return {
		width = 3,
		depth = 2,
		bricks = {
			brick(0, 5, 0, "input"),
			brick(9, 0, 0, "output"),
			brick(5, 3, 0),
			brick(0, 1, 1, "input"),
			brick(5, 5, 0, "output"),
		},
	}
end

test("the footprint is the baseplate, turned on E and W", function()
	local v = asymmetric()
	local w, d = Placement.footprint(v, "N")
	assertEqual(3, w)
	assertEqual(2, d)
	w, d = Placement.footprint(v, "E")
	assertEqual(2, w)
	assertEqual(3, d)
	w, d = Placement.footprint(v, "S")
	assertEqual(3, w)
	assertEqual(2, d)
	w, d = Placement.footprint(v, "W")
	assertEqual(2, w)
	assertEqual(3, d)
end)

-- Ports in brick order: { kind, side, x, y }, x/y the world tile the port
-- faces for a building with its footprint's north-west tile on (10, 10).
local function portsAt(facing)
	return Placement.ports(asymmetric(), facing, 10, 10, CFG)
end

local function assertPort(port, kind, side, x, y)
	assertEqual(kind, port.kind)
	assertEqual(side, port.side, kind .. " side")
	assertEqual(x, port.x, kind .. " x")
	assertEqual(y, port.y, kind .. " y")
end

test("port tiles lie just outside the footprint edge in every facing", function()
	local n = portsAt("N")
	assertEqual(2, #n, "only ground-level edge bricks are ports")
	assertPort(n[1], "input", "W", 9, 11)
	assertPort(n[2], "output", "N", 12, 9)

	local e = portsAt("E")
	assertPort(e[1], "input", "N", 10, 9)
	assertPort(e[2], "output", "E", 12, 12)

	local s = portsAt("S")
	assertPort(s[1], "input", "E", 13, 10)
	assertPort(s[2], "output", "S", 10, 12)

	local w = portsAt("W")
	assertPort(w[1], "input", "S", 11, 13)
	assertPort(w[2], "output", "W", 9, 10)
end)

test("a port brick in a footprint corner faces the north or south edge", function()
	local v = { width = 1, depth = 1, bricks = { brick(0, 0, 0, "input"), brick(3, 3, 0, "output") } }
	local ports = Placement.ports(v, "N", 0, 0, CFG)
	assertPort(ports[1], "input", "N", 0, -1)
	assertPort(ports[2], "output", "S", 0, 1)
end)

test("a port brick spanning two tiles faces the tile under its centre", function()
	local wide = brick(3, 0, 0, "output")
	wide.width = 2
	local ports = Placement.ports({ width = 2, depth = 1, bricks = { wide } }, "N", 0, 0, CFG)
	assertPort(ports[1], "output", "N", 1, -1)
end)

local Cost = require("src.game.builder.cost")

test("a version costs its baseplate per tile plus its bricks", function()
	local cost = Cost.of(asymmetric(), Config)
	local bricks = 5 * Config.costs.perStud.plank.plank -- five 1x1 plank bricks
	assertEqual(6 * Config.costs.baseplatePerTile.plank + bricks, cost.plank)
end)

local Session = require("src.game.session")
local World = require("src.game.world")
local Inventory = require("src.game.components.inventory")

local DESIGN = { id = "d1", name = "Hall", versions = { asymmetric() } }

local function newSession()
	local ctx = Session.new(World.new(20, 20), Config, 1)
	return ctx, ctx.pools.characters[1]
end

-- One step with player 1 asking to place DESIGN v1.
local function place(ctx, facing, x, y)
	ctx.intents[1] = { x = 0, y = 0, place = { design = DESIGN, version = 1, facing = facing, tileX = x, tileY = y } }
	Session.advance(ctx, 1 / 60)
	ctx.intents[1] = nil
end

test("placing creates a building with the version, facing and an empty buffer per port", function()
	local ctx = newSession()
	place(ctx, "E", 2, 3)

	assertEqual(1, #ctx.pools.buildings)
	local b = ctx.pools.buildings[1]
	assertEqual(DESIGN, b.design)
	assertEqual(1, b.version)
	assertEqual("E", b.facing)
	assertEqual(2, b.tileX)
	assertEqual(3, b.tileY)
	assertEqual(2, b.width)
	assertEqual(3, b.depth)
	assertEqual(2, #b.ports)
	assertEqual("input", b.ports[1].kind)
	assertEqual(2, b.ports[1].x)
	assertEqual(2, b.ports[1].y)
	assertEqual(nil, next(b.ports[1].buffer.counts), "buffer starts empty")
	assertEqual(nil, next(b.ports[2].buffer.counts), "buffer starts empty")
end)

test("a building occupies its footprint, blocks it and marks its port tiles", function()
	local ctx = newSession()
	place(ctx, "E", 2, 3)
	local b = ctx.pools.buildings[1]

	for y = 3, 5 do
		for x = 2, 3 do
			assertEqual(b, World.buildingAt(ctx.world, x, y))
			assertTrue(World.isBlocked(ctx.world, x, y))
		end
	end
	assertEqual(nil, World.buildingAt(ctx.world, 4, 3))
	assertFalse(World.isBlocked(ctx.world, 4, 3))

	assertEqual(b.ports[1], World.portAt(ctx.world, 2, 2))
	assertEqual(b.ports[2], World.portAt(ctx.world, 4, 5))
	assertFalse(World.isBlocked(ctx.world, 2, 2), "port tiles stay walkable")
end)

test("placing pays the cost from the character's inventory, once", function()
	local ctx, c = newSession()
	local before = Inventory.count(c.inventory, "plank")
	local cost = Cost.of(asymmetric(), Config).plank

	place(ctx, "N", 2, 3)
	Session.advance(ctx, 1 / 60)
	Session.advance(ctx, 1 / 60)

	assertEqual(before - cost, Inventory.count(c.inventory, "plank"))
	assertEqual(Config.stockpile.stone, Inventory.count(c.inventory, "stone"))
end)

local function request(facing, x, y)
	return { design = DESIGN, version = 1, facing = facing, tileX = x, tileY = y }
end

-- Placement.check's answer for DESIGN v1 facing N at (5, 5): footprint
-- (5..7, 5..6), input port tile (4, 6), output port tile (7, 4).
local function check(ctx, c, x, y)
	return Placement.check(ctx, request("N", x or 5, y or 5), c.inventory)
end

test("a placement on clear grass with the cost in hand is valid", function()
	local ctx, c = newSession()
	local ok, reason = check(ctx, c)
	assertTrue(ok)
	assertEqual(nil, reason)
end)

test("a placement is refused with why, and nothing is placed or paid", function()
	local cases = {
		{
			reason = "water",
			setup = function(ctx)
				World.setTerrain(ctx.world, 7, 6, "water")
			end,
		},
		{
			reason = "node",
			setup = function(ctx)
				World.addNode(ctx.world, { id = 1, kind = "rock", tileX = 6, tileY = 5, variant = 1, stage = 1, amount = 1 })
			end,
		},
		{
			reason = "building",
			setup = function(ctx)
				place(ctx, "N", 7, 1) -- footprint 7..9 x 1..2
			end,
			x = 6,
			y = 2,
		},
		{
			reason = "port blocked",
			setup = function(ctx)
				World.setTerrain(ctx.world, 4, 6, "water")
			end,
		},
		{
			reason = "port blocked",
			setup = function() end,
			x = 0,
			y = 5,
		},
		{
			reason = "outside",
			setup = function() end,
			x = 18,
			y = 5,
		},
		{
			reason = "unaffordable",
			setup = function(_, c)
				c.inventory.counts.plank = Cost.of(asymmetric(), Config).plank - 1
			end,
		},
	}
	for _, case in ipairs(cases) do
		local ctx, c = newSession()
		case.setup(ctx, c)
		local built = #ctx.pools.buildings
		local planks = Inventory.count(c.inventory, "plank")

		local ok, reason = check(ctx, c, case.x, case.y)
		assertFalse(ok, case.reason .. ": expected refusal")
		assertEqual(case.reason, reason)

		place(ctx, "N", case.x or 5, case.y or 5)
		assertEqual(built, #ctx.pools.buildings, case.reason .. ": nothing placed")
		assertEqual(planks, Inventory.count(c.inventory, "plank"), case.reason .. ": nothing paid")
	end
end)
