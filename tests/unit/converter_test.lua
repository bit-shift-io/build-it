-- Saw bench converters (docs/CONTEXT.md "Function brick", "Operator job"):
-- 2 logs from an input buffer become 1 plank, but only while a villager
-- holds the bench's operator job. The operator carries the logs to the
-- bench's tile, waits one cycle and carries the plank to an output port.
local Session = require("src.game.session")
local World = require("src.game.world")
local Config = require("src.game.config")
local Placement = require("src.game.buildings.placement")
local Inventory = require("src.game.components.inventory")
local Ports = require("src.game.components.ports")
local Storage = require("src.game.components.storage")

local TILE = Config.tileSize
local STEP = 1 / 60

local Designs = require("tests.support.designs")

-- A 2x1 tile design: `n` saw benches, one a tile from the west, an input
-- port (south, tile 0) and an output port (south, tile 1).
local function design(n)
	local roles = { Designs.port("input", 0.25, 1), Designs.port("output", 1.25, 1) }
	for i = 1, n do
		table.insert(roles, Designs.ability("sawbench", i - 0.5, 0.25))
	end
	return Designs.floor(2, 1, unpack(roles))
end

local function setup(n)
	local ctx = Session.new(World.new(30, 30), Config, 1)
	local b = assert(Placement.build(ctx, Designs.request(design(n), "N", 10, 10)))
	return ctx, b
end

local function villager(ctx, tileX, tileY)
	local v = Session.newVillager(#ctx.pools.villagers + 1, (tileX + 0.5) * TILE, (tileY + 0.5) * TILE, Config)
	table.insert(ctx.pools.villagers, v)
	return v
end

local function run(ctx, seconds)
	for _ = 1, math.floor(seconds / STEP + 0.5) do
		Session.advance(ctx, STEP)
	end
end

local function ports(b)
	local input, output
	for _, p in ipairs(b.ports) do
		if p.kind == "input" then
			input = p
		else
			output = p
		end
	end
	return input, output
end

local function fill(store, item, n)
	for _ = 1, n do
		Storage.add(store, item)
	end
end

test("a saw bench with logs and no villager stays idle", function()
	local ctx, b = setup(1)
	local input, output = ports(b)
	fill(input.buffer, "log", 4)
	run(ctx, 30)
	assertEqual(4, input.buffer.counts.log)
	assertEqual(nil, output.buffer.counts.plank)
	assertEqual("idle", b.functionBricks[1].state)
end)

-- Runs up to `seconds`, noting each new tile `v` stands on, until done().
local function trace(ctx, v, seconds, done)
	local tiles = {}
	for _ = 1, math.floor(seconds / STEP + 0.5) do
		Session.advance(ctx, STEP)
		local x, y = math.floor(v.x / TILE), math.floor(v.y / TILE)
		local last = tiles[#tiles]
		if not last or last.x ~= x or last.y ~= y then
			tiles[#tiles + 1] = { x = x, y = y }
		end
		if done and done() then
			break
		end
	end
	return tiles
end

-- The index in `tiles` of the first visit to (x, y) after index `from`.
local function visit(tiles, x, y, from)
	for i = (from or 0) + 1, #tiles do
		if tiles[i].x == x and tiles[i].y == y then
			return i
		end
	end
end

test("an operator carries 2 logs from the input to the bench, waits a cycle, and drops 1 plank at the output", function()
	local ctx, b = setup(1)
	local input, output = ports(b)
	local fb = b.functionBricks[1]
	fill(input.buffer, "log", 2)
	local v = villager(ctx, 4, 4)

	local tiles = trace(ctx, v, 60, function()
		return output.buffer.counts.plank ~= nil
	end)
	assertEqual(1, output.buffer.counts.plank)
	assertEqual(nil, input.buffer.counts.log)
	local i = visit(tiles, input.x, input.y)
	local j = visit(tiles, fb.tileX, fb.tileY, i)
	local k = visit(tiles, output.x, output.y, j)
	assertTrue(i and j and k, "walked input, then the bench's tile, then the output")
	assertTrue(World.buildingAt(ctx.world, fb.tileX, fb.tileY) == b, "the bench's tile is inside the footprint")
	run(ctx, STEP * 2)
	assertEqual(nil, v.job, "no logs left: the operator lets go")
	assertTrue(v.load.count == 0, "empty-handed")
end)

test("the operator stays for a second cycle while logs remain, then lets go", function()
	local ctx, b = setup(1)
	local input, output = ports(b)
	fill(input.buffer, "log", 4)
	local v = villager(ctx, 4, 4)
	run(ctx, STEP)
	local job = assert(v.job, "the villager took the operator job")
	assertEqual("operate", job.kind)

	trace(ctx, v, 60, function()
		return output.buffer.counts.plank == 1
	end)
	run(ctx, STEP)
	assertTrue(v.job == job, "still the same job after the first plank")
	trace(ctx, v, 60, function()
		return output.buffer.counts.plank == 2
	end)
	assertEqual(nil, input.buffer.counts.log)
	run(ctx, STEP)
	assertEqual(nil, v.job)
	assertTrue(job.dead)
	assertEqual(nil, b.functionBricks[1].operator)
end)

test("the operator lets go when the outputs are full", function()
	local ctx, b = setup(1)
	local input, output = ports(b)
	fill(input.buffer, "log", 4)
	fill(output.buffer, "plank", output.buffer.capacity - 1)
	local v = villager(ctx, 4, 4)
	trace(ctx, v, 60, function()
		return output.buffer.counts.plank == output.buffer.capacity
	end)
	run(ctx, STEP * 2)
	assertEqual(nil, v.job)
	assertEqual(2, input.buffer.counts.log, "logs wait for room")
	run(ctx, 20)
	assertEqual(nil, v.job, "no work while the outputs are full")
	assertEqual(2, input.buffer.counts.log)
end)

test("two saw benches in one building get two operators", function()
	local ctx, b = setup(2)
	local input, output = ports(b)
	fill(input.buffer, "log", 4)
	local v1, v2, v3 = villager(ctx, 4, 4), villager(ctx, 5, 4), villager(ctx, 25, 25)
	run(ctx, STEP)
	assertTrue(v1.job and v2.job and v1.job ~= v2.job, "the two nearest villagers took a job each")
	assertTrue(v1.job.brick ~= v2.job.brick, "one per bench")
	assertEqual(nil, v3.job)
	trace(ctx, v1, 60, function()
		return output.buffer.counts.plank == 2
	end)
	assertEqual(2, output.buffer.counts.plank)
end)

test("delivery caps at buffer space and rejects unconsumed items", function()
	local ctx, b = setup(1)
	local c = ctx.pools.characters[1]
	c.inventory = Inventory.new({})
	local input = ports(b)
	Inventory.add(c.inventory, "log", 100)
	Inventory.add(c.inventory, "stone", 5)
	Ports.deliver(input, b, c.inventory)
	assertEqual(input.buffer.capacity, input.buffer.counts.log)
	assertEqual(100 - input.buffer.capacity, Inventory.count(c.inventory, "log"))
	assertEqual(nil, input.buffer.counts.stone)
	assertEqual(5, Inventory.count(c.inventory, "stone"))
end)
