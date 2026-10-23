local Session = require("src.game.session")
local Builtins = require("tests.support.builtins")
local WorldGen = require("src.game.world_gen")
local World = require("src.game.world")
local Config = require("src.game.config")
local AnimalSystem = require("src.game.systems.animal_system")

local STEP = 1 / 60

local function run(ctx, seconds)
	for _ = 1, math.floor(seconds / STEP + 0.5) do
		Session.advance(ctx, STEP)
	end
end

local function tileOf(a)
	return math.floor(a.x / Config.tileSize), math.floor(a.y / Config.tileSize)
end

-- An open world with one herd of `n` deer (cap `cap`) homed on tile (20, 20).
local function herdWorld(n, cap, world)
	local ctx = Session.new(world or World.new(40, 40), Config, 1)
	local herd = AnimalSystem.addHerd(ctx, 20, 20, cap)
	for i = 1, n do
		AnimalSystem.spawn(ctx, herd, 20 + i % 2, 20)
	end
	return ctx, herd
end

test("the same seed spawns the same herds, and different seeds differ", function()
	local function signature(seed)
		local ctx = Session.newGame(WorldGen.generate(Config, seed), Config, seed, Builtins)
		local parts = {}
		for _, h in ipairs(ctx.pools.herds) do
			parts[#parts + 1] = string.format("h%d@%d,%d/%d", h.id, h.tileX, h.tileY, h.cap)
		end
		for _, a in ipairs(ctx.pools.animals) do
			parts[#parts + 1] = string.format("d%d h%d @%.1f,%.1f", a.id, a.herd, a.x, a.y)
		end
		return table.concat(parts, "|")
	end
	assertTrue(#Session.newGame(WorldGen.generate(Config, 1), Config, 1, Builtins).pools.herds > 0, "expected herds")
	assertEqual(signature(2), signature(2))
	assertTrue(signature(2) ~= signature(3))
end)

test("new-game deer stand on standable tiles, each herd at its cap", function()
	for seed = 1, 3 do
		local ctx = Session.newGame(WorldGen.generate(Config, seed), Config, seed, Builtins)
		local counts = {}
		for _, a in ipairs(ctx.pools.animals) do
			local x, y = tileOf(a)
			assertTrue(World.isStandable(ctx.world, x, y), "deer on a standable tile")
			counts[a.herd] = (counts[a.herd] or 0) + 1
		end
		for _, h in ipairs(ctx.pools.herds) do
			assertEqual(h.cap, counts[h.id], "herd " .. h.id .. " at its cap")
		end
	end
end)

test("deer wander but stay within the herd's home radius, off water and footprints", function()
	local world = World.new(40, 40)
	for y = 19, 21 do
		for x = 22, 24 do
			World.setTerrain(world, x, y, "water")
		end
	end
	local ctx, herd = herdWorld(3, 6, world)
	-- a detour round the pond may step just outside the radius
	local r = Config.animals.deer.wanderRadius
	local start = {}
	for i, a in ipairs(ctx.pools.animals) do
		start[i] = { a.x, a.y }
	end
	local moved = false
	for _ = 1, 20 do
		run(ctx, 5)
		for i, a in ipairs(ctx.pools.animals) do
			local x, y = tileOf(a)
			assertTrue(math.max(math.abs(x - herd.tileX), math.abs(y - herd.tileY)) <= r + 2, "deer strayed to " .. x .. "," .. y)
			assertTrue(World.terrainAt(ctx.world, x, y) ~= "water", "deer in water")
			moved = moved or a.x ~= start[i][1] or a.y ~= start[i][2]
		end
	end
	assertTrue(moved, "expected the deer to wander")
end)

test("a herd below its cap grows by one after the breed interval; at its cap it does not", function()
	local ctx, herd = herdWorld(2, 3)
	run(ctx, Config.animals.deer.breedEvery - 5)
	assertEqual(2, #ctx.pools.animals)
	run(ctx, 6)
	assertEqual(3, #ctx.pools.animals)
	assertEqual(herd.id, ctx.pools.animals[3].herd)
	run(ctx, Config.animals.deer.breedEvery * 2)
	assertEqual(3, #ctx.pools.animals)
end)

test("a dead deer leaves the pool in the despawn sweep and the herd breeds back", function()
	local ctx = herdWorld(3, 3)
	ctx.pools.animals[1].dead = true
	assertEqual(3, #ctx.pools.animals)
	run(ctx, STEP)
	assertEqual(2, #ctx.pools.animals)
	run(ctx, Config.animals.deer.breedEvery + 1)
	assertEqual(3, #ctx.pools.animals)
end)
