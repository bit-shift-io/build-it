-- Beds and the sleep job (src/game/jobs/sleep.lua, docs/CONTEXT.md "Bed",
-- "Tiredness"): a tired villager reserves the nearest free bed and sleeps
-- there until tiredness is 0; with no free bed it sleeps where it stands,
-- more slowly. Needs yield at job boundaries (ADR 0004).
local Session = require("src.game.session")
local World = require("src.game.world")
local Config = require("src.game.config")
local Placement = require("src.game.buildings.placement")
local Storage = require("src.game.components.storage")
local Status = require("src.game.components.status")
local FunctionBrick = require("src.game.components.function_brick")
local Walls = require("tests.support.walls")

local TILE = Config.tileSize
local STEP = 1 / 60
local NEEDS = Config.needs

local Designs = require("tests.support.designs")

-- A 2x2 bedroom: a bed in its north-west tile, no ports.
local BED = Designs.floor(2, 2, Designs.ability("bed", 0.25, 0.25))

local STORE = Designs.floor(1, 1,
	Designs.ability("depot", 0.25, 0.125),
	Designs.storage(8, 0.75, 0.125),
	Designs.port("input", 0.25, 1),
	Designs.port("output", 0.75, 1))

local function place(ctx, design, x, y)
	return Placement.build(ctx, Designs.request(design, "N", x, y))
end

local function villager(ctx, tileX, tileY)
	local v = Session.newVillager(#ctx.pools.villagers + 1, (tileX + 0.5) * TILE, (tileY + 0.5) * TILE, Config)
	v.name = "V" .. #ctx.pools.villagers
	table.insert(ctx.pools.villagers, v)
	return v
end

local function newCtx()
	return Session.new(World.new(30, 30), Config, 1)
end

local function run(ctx, seconds)
	for _ = 1, math.floor(seconds / STEP + 0.5) do
		Session.advance(ctx, STEP)
	end
end

-- Seconds until `v` has no job, at most `limit`.
local function untilAwake(ctx, v, limit)
	for i = 1, math.floor(limit / STEP) do
		Session.advance(ctx, STEP)
		if not v.job then
			return i * STEP
		end
	end
end

test("a bed counts as a function brick and needs no operator", function()
	local ctx = newCtx()
	local b = place(ctx, BED, 4, 2)
	assertEqual(1, #b.functionBricks)
	assertTrue(b.functionBricks[1].bed, "bed record")
	assertEqual(false, FunctionBrick.hasWork(b.functionBricks[1], b, ctx))
end)

test("a tired villager walks into a free bed, sleeps and wakes at 0 tiredness", function()
	local ctx = newCtx()
	local b = place(ctx, BED, 4, 2)
	local fb = b.functionBricks[1]
	local v = villager(ctx, 6, 9)
	v.needs.tiredness = NEEDS.tiredAt

	run(ctx, 0.1)
	assertEqual("sleep", v.job and v.job.kind)
	assertEqual(v.job, fb.occupant)
	assertEqual(b, v.mover.enter)

	local asleep
	for _ = 1, 20 * 60 do
		Session.advance(ctx, STEP)
		if v.job.stage == "sleeping" then
			asleep = true
			break
		end
	end
	assertTrue(asleep, "reached the bed")
	assertEqual("Sleeping", Status.activity(v))
	assertEqual(fb.tileX, math.floor(v.x / TILE))
	assertEqual(fb.tileY, math.floor(v.y / TILE))

	assertTrue(untilAwake(ctx, v, 120) ~= nil, "woke")
	assertTrue(v.needs.tiredness <= 0.001, "rested")
	assertEqual(nil, fb.occupant)
	assertEqual(nil, v.mover.enter)
end)

-- A walled 2x2 bedroom, walls a voxel thick and body high, one 2-stud
-- door in the middle of the south wall, and the bed prefab in the
-- north-west corner behind an inner wall along row 4 (columns 0..5).
local function wall(x, y, w, d)
	return string.format("box{ size = { %g, %g, 0.5 }, transform = { move = { %g, %g, 0.0625 } } }", w, d, x, y)
end
local WALLED_BED = Designs.floor(2, 2,
	wall(0, 0, 2, 0.0625), wall(0, 0, 0.0625, 2), wall(1.9375, 0, 0.0625, 2),
	wall(0, 1.9375, 0.75, 0.0625), wall(1.25, 1.9375, 0.75, 0.0625),
	wall(0, 1, 1.5, 0.0625),
	'prefab("bed", { transform = { move = { 0.25, 0.25, 0.0625 } } })')

local function inWall(v, b)
	return Walls.under(v, b, Config) ~= nil
end

test("a tired villager walks through the door to its bed, never crossing a wall, and walks out after", function()
	local ctx = newCtx()
	local b = place(ctx, WALLED_BED, 4, 2)
	local fb = b.functionBricks[1]
	local v = villager(ctx, 5, 0)
	v.needs.tiredness = NEEDS.tiredAt

	local asleep
	for _ = 1, 30 * 60 do
		Session.advance(ctx, STEP)
		assertFalse(inWall(v, b), "overlaps a wall at " .. v.x .. "," .. v.y)
		if v.job and v.job.stage == "sleeping" then
			asleep = true
			break
		end
	end
	assertTrue(asleep, "reached the bed")
	assertEqual(b, World.buildingAt(ctx.world, math.floor(v.x / TILE), math.floor(v.y / TILE)))
	local d = math.max(math.abs(v.x / TILE - fb.pointX), math.abs(v.y / TILE - fb.pointY))
	assertTrue(d <= 0.5, "beside the bed, " .. d .. " tiles off")

	v.needs.tiredness = 0.001
	local out
	for _ = 1, 30 * 60 do
		Session.advance(ctx, STEP)
		assertFalse(inWall(v, b), "overlaps a wall at " .. v.x .. "," .. v.y)
		if not v.job and World.buildingAt(ctx.world, math.floor(v.x / TILE), math.floor(v.y / TILE)) == nil then
			out = true
			break
		end
	end
	assertTrue(out, "woke and walked out")
end)

test("sleeping in a bed takes about a minute from the tired threshold", function()
	local ctx = newCtx()
	local b = place(ctx, BED, 4, 2)
	local fb = b.functionBricks[1]
	local v = villager(ctx, fb.tileX, fb.tileY)
	v.needs.tiredness = NEEDS.tiredAt
	local slept = 0
	for _ = 1, 200 * 60 do
		Session.advance(ctx, STEP)
		if not v.job then
			break
		end
		if v.job.stage == "sleeping" then
			slept = slept + STEP
		end
	end
	assertTrue(slept > 55 and slept < 65, "bed sleep took " .. slept)
end)

test("a second tired villager sleeps rough, three times slower", function()
	local ctx = newCtx()
	local b = place(ctx, BED, 4, 2)
	local fb = b.functionBricks[1]
	local a = villager(ctx, fb.tileX, fb.tileY)
	local rough = villager(ctx, 20, 20)
	a.needs.tiredness, rough.needs.tiredness = NEEDS.tiredAt, NEEDS.tiredAt

	run(ctx, 0.1)
	assertEqual(a.job, fb.occupant)
	assertEqual("sleep", rough.job.kind)
	assertEqual(nil, rough.job.brick)
	assertEqual("Sleeping rough", Status.activity(rough))
	assertEqual(nil, rough.mover.enter)

	local x, y = rough.x, rough.y
	local slept = 0
	for _ = 1, 400 * 60 do
		Session.advance(ctx, STEP)
		if not rough.job then
			break
		end
		slept = slept + STEP
	end
	assertEqual(x, rough.x)
	assertEqual(y, rough.y)
	assertTrue(slept > 175 and slept < 185, "ground sleep took " .. slept)
end)

test("hunger still rises while asleep", function()
	local ctx = newCtx()
	local v = villager(ctx, 5, 5)
	v.needs.tiredness = NEEDS.tiredAt
	run(ctx, 10)
	assertEqual("sleep", v.job.kind)
	assertTrue(v.needs.hunger > 0.03, "hungry while asleep")
end)

test("a sleeper that turns hungry wakes and eats first when there is food", function()
	local ctx = newCtx()
	local store = place(ctx, STORE, 4, 2)
	Storage.add(store.ports[2].buffer, "berry")
	Storage.add(store.ports[2].buffer, "berry")
	Storage.add(store.ports[2].buffer, "berry")
	local v = villager(ctx, 6, 8)
	v.needs.tiredness = NEEDS.tiredAt
	v.needs.hunger = NEEDS.hungryAt - 0.01

	run(ctx, 0.5)
	assertEqual("sleep", v.job.kind)
	local ate = false
	for _ = 1, 60 * 60 do
		Session.advance(ctx, STEP)
		if v.job and v.job.kind == "eat" then
			ate = true
			break
		end
	end
	assertTrue(ate, "woke to eat")
end)

test("a hungry sleeper with no food sleeps on", function()
	local ctx = newCtx()
	local v = villager(ctx, 6, 8)
	v.needs.tiredness = NEEDS.tiredAt
	v.needs.hunger = NEEDS.hungryAt
	run(ctx, 5)
	assertEqual("sleep", v.job.kind)
	assertTrue(not v.job.dead, "still asleep")
end)

test("removing a bed's building wakes its sleeper", function()
	local ctx = newCtx()
	local b = place(ctx, BED, 4, 2)
	local fb = b.functionBricks[1]
	local v = villager(ctx, fb.tileX, fb.tileY)
	v.needs.tiredness = NEEDS.tiredAt
	run(ctx, 1)
	local job = v.job
	assertEqual(fb, job.brick)

	b.dead = true
	run(ctx, 0.05)
	assertEqual(true, job.dead)
	assertEqual(nil, fb.occupant)
	assertEqual(nil, v.mover.enter)
end)

test("a tired operator finishes its cycle then yields to sleep", function()
	local ctx = newCtx()
	local v = villager(ctx, 5, 5)
	v.needs.tiredness = NEEDS.tiredAt
	local Operate = require("src.game.jobs.operate")
	local job = { kind = "operate", building = { dead = false }, brick = { ability = "saw" }, villager = v,
		work = { begin = function() error("must not start a cycle") end } }
	v.job = job
	v.mover.enter = job.building
	Operate.done(job, ctx)
	assertEqual(true, job.dead)
	assertEqual(nil, v.job)
end)
