-- Saw bench converters (docs/CONTEXT.md "Function brick"): 2 logs from
-- input buffers or storage become 1 plank; delivery caps at buffer space.
local Session = require("src.game.session")
local World = require("src.game.world")
local Config = require("src.game.config")
local Placement = require("src.game.buildings.placement")
local Inventory = require("src.game.components.inventory")
local FunctionBrick = require("src.game.components.function_brick")
local Ports = require("src.game.components.ports")
local Storage = require("src.game.components.storage")

local STEP = 1 / 60

local function brick(shape, x, y, f)
	return { x = x, y = y, z = 0, width = f.width, depth = f.depth, height = 1, shape = shape, rotation = 0, material = "plank", paint = 1, ability = f.ability, port = f.port, storage = f.storage }
end

-- A 2x1 tile design: `n` saw benches, an input port (south, tile 0) and an
-- output port (south, tile 1).
local function design(n, storage)
	local bricks = {
		brick("input", 0, 3, { width = 2, depth = 1, port = "input" }),
		brick("output", 4, 3, { width = 2, depth = 1, port = "output" }),
	}
	for i = 1, n do
		table.insert(bricks, brick("sawbench", (i - 1) * 4, 0, { width = 4, depth = 2, ability = "sawbench" }))
	end
	if storage then
		table.insert(bricks, brick("storage", 0, 2, { width = 2, depth = 1, storage = storage }))
	end
	return { id = "d1", name = "Mill", versions = { { width = 2, depth = 1, bricks = bricks } } }
end

local function setup(n, storage)
	local ctx = Session.new(World.new(30, 30), Config, 1)
	local c = ctx.pools.characters[1]
	c.inventory = Inventory.new({ plank = 10000, stone = 10000 })
	local b = assert(Placement.place(ctx, c, { design = design(n, storage), version = 1, facing = "N", tileX = 10, tileY = 10 }))
	return ctx, c, b
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

test("a converter waits for 2 logs, then turns them into 1 plank", function()
	local ctx, c, b = setup(1)
	local input, output = ports(b)
	local cycle = FunctionBrick.cycle(b.traits, Config, Config.production.recipes.sawbench.cycle)
	Storage.add(input.buffer, "log")
	run(ctx, cycle * 2)
	assertEqual(1, input.buffer.counts.log)
	assertEqual(nil, output.buffer.counts.plank)

	Storage.add(input.buffer, "log")
	run(ctx, cycle * 0.5)
	assertEqual(nil, input.buffer.counts.log, "logs consumed")
	assertEqual(nil, output.buffer.counts.plank)
	run(ctx, cycle * 0.6)
	assertEqual(1, output.buffer.counts.plank)
end)

test("a converter stalls on a full output and resumes when it frees", function()
	local ctx, c, b = setup(1)
	local input, output = ports(b)
	local cycle = FunctionBrick.cycle(b.traits, Config, Config.production.recipes.sawbench.cycle)
	for _ = 1, output.buffer.capacity do
		Storage.add(output.buffer, "plank")
	end
	Storage.add(input.buffer, "log")
	Storage.add(input.buffer, "log")
	run(ctx, cycle * 2)
	assertEqual("full", b.functionBricks[1].state)
	assertEqual(output.buffer.capacity, output.buffer.counts.plank)

	Ports.collect(output, c.inventory)
	run(ctx, STEP * 2)
	assertEqual(1, output.buffer.counts.plank)
end)

test("a converter pulls logs from storage", function()
	local ctx, c, b = setup(1, 8)
	local _, output = ports(b)
	Storage.add(b.storage, "log")
	Storage.add(b.storage, "log")
	run(ctx, Config.production.recipes.sawbench.cycle * 2)
	assertEqual(1, output.buffer.counts.plank)
end)

test("two saw benches convert in parallel", function()
	local ctx, c, b = setup(2)
	local input, output = ports(b)
	for _ = 1, 4 do
		Storage.add(input.buffer, "log")
	end
	local cycle = FunctionBrick.cycle(b.traits, Config, Config.production.recipes.sawbench.cycle)
	run(ctx, cycle + STEP * 2)
	assertEqual(2, output.buffer.counts.plank)
end)

test("delivery caps at buffer space and rejects unconsumed items", function()
	local ctx, c, b = setup(1)
	local input = ports(b)
	Inventory.add(c.inventory, "log", 100)
	Inventory.add(c.inventory, "stone", 5)
	local stone = Inventory.count(c.inventory, "stone")
	Ports.deliver(input, b, c.inventory)
	assertEqual(input.buffer.capacity, input.buffer.counts.log)
	assertEqual(100 - input.buffer.capacity, Inventory.count(c.inventory, "log"))
	assertEqual(nil, input.buffer.counts.stone)
	assertEqual(stone, Inventory.count(c.inventory, "stone"))
end)
