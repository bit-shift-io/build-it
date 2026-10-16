local Mover = require("src.game.components.mover")

-- A ctx with only what Mover reads: dt, and a world large enough that no
-- edge is reached.
local function ctxWith(dt)
	return { dt = dt, world = { width = 100, height = 100 }, config = { tileSize = 32 } }
end

local function record(x, y, speed)
	return { x = x, y = y, size = 16, mover = { speed = speed } }
end

test("Mover.apply moves speed * dt along the intent direction", function()
	local r = record(500, 500, 120)
	Mover.apply(r, { x = 1, y = 0 }, ctxWith(1 / 60))
	assertNear(502, r.x)
	assertNear(500, r.y)
end)

test("Mover.apply moves diagonally at the same speed as straight", function()
	local r = record(500, 500, 120)
	Mover.apply(r, { x = 1, y = 1 }, ctxWith(1))
	local dx, dy = r.x - 500, r.y - 500
	assertNear(120, math.sqrt(dx * dx + dy * dy), 0.0001)
	assertNear(dx, dy)
end)

test("Mover.apply stops the record at the world edge, keeping it fully inside", function()
	-- 100 tiles * 32 px = 3200 px wide; a 16 px record's centre stops 8 px in.
	local r = record(3190, 10, 120)
	Mover.apply(r, { x = 1, y = -1 }, ctxWith(1))
	assertNear(3192, r.x)
	assertNear(8, r.y)
end)

local World = require("src.game.world")

local function footprintCtx()
	local world = World.new(10, 10)
	World.addBuilding(world, { tileX = 3, tileY = 0, width = 1, depth = 10, ports = {} })
	return { dt = 0.1, world = world, config = { tileSize = 32 } }
end

test("Mover.apply stops a record at a building footprint", function()
	local r = record(80, 48, 120)
	Mover.apply(r, { x = 1, y = 0 }, footprintCtx())
	assertNear(96 - 8, r.x)
end)

test("Mover.apply walks a record with mover.throughBuildings through a footprint", function()
	local r = record(80, 48, 120)
	r.mover.throughBuildings = true
	Mover.apply(r, { x = 1, y = 0 }, footprintCtx())
	assertNear(92, r.x)
end)
