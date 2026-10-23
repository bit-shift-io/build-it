-- Free villagers gather (docs/CONTEXT.md "Free villager", "Gather area"):
-- a villager with no job walks to a standable tile near the nearest storage
-- facility, or to the nearest standable tile when there is none.
local Session = require("src.game.session")
local Builtins = require("tests.support.builtins")
local World = require("src.game.world")
local Config = require("src.game.config")
local Walker = require("src.game.components.walker")
local Placement = require("src.game.buildings.placement")
local Starter = require("src.game.designs.starter")
local Idle = require("src.game.components.idle")

local TILE = Config.tileSize
local STEP = 1 / 60

local function newGame(seed)
	local ctx = Session.newGame(World.new(60, 60), Config, seed or 1, Builtins)
	ctx.pools.villagers = {}
	return ctx, ctx.pools.buildings[1]
end

local function addVillager(ctx, tx, ty)
	local id = #ctx.pools.villagers + 1
	local v = Session.newVillager(id, (tx + 0.5) * TILE, (ty + 0.5) * TILE, Config)
	table.insert(ctx.pools.villagers, v)
	return v
end

local function run(ctx, seconds)
	for _ = 1, math.floor(seconds * 60) do
		Session.advance(ctx, STEP)
	end
end

local function tileOf(v)
	return math.floor(v.x / TILE), math.floor(v.y / TILE)
end

local function inGatherArea(ctx, b, x, y)
	for _, t in ipairs(Idle.gatherTiles(ctx, b)) do
		if t.x == x and t.y == y then
			return true
		end
	end
	return false
end

test("a villager on a port tile ends on a standable gather tile, off footprint and ports", function()
	local ctx, b = newGame()
	local p = b.ports[1]
	local v = addVillager(ctx, p.x, p.y)
	run(ctx, 20)
	local x, y = tileOf(v)
	assertTrue(World.isStandable(ctx.world, x, y))
	assertEqual(nil, World.buildingAt(ctx.world, x, y))
	assertEqual(nil, World.portAt(ctx.world, x, y))
	assertTrue(inGatherArea(ctx, b, x, y), "ended outside the gather area")
	assertEqual("settled", v.idle.phase)
end)

test("a settled villager caught under a new footprint walks out and settles on a standable tile", function()
	local ctx, b = newGame()
	local t = Idle.gatherTiles(ctx, b)[1]
	local v = addVillager(ctx, t.x, t.y)
	run(ctx, 1)
	assertEqual("settled", v.idle.phase)
	assertTrue(Walker.idle(v.walker))

	-- A 3x3 footprint lands on it, the villager at its centre tile.
	local over = { tileX = t.x - 1, tileY = t.y - 1, width = 3, depth = 3, ports = {} }
	World.addBuilding(ctx.world, over)
	run(ctx, 6)
	local x, y = tileOf(v)
	assertTrue(World.isStandable(ctx.world, x, y), "ended on " .. x .. "," .. y)
	assertEqual("settled", v.idle.phase)
	assertTrue(Walker.idle(v.walker))
end)

test("a free villager carrying a load gathers and keeps the load", function()
	-- No facility, so no haul job takes the load.
	local world = World.new(20, 20)
	World.setTerrain(world, 10, 10, "water")
	local ctx = Session.new(world, Config, 1)
	local v = Session.newVillager(1, 10.5 * TILE, 10.5 * TILE, Config)
	v.load.item, v.load.count = "log", 2
	ctx.pools.villagers = { v }
	run(ctx, 5)
	local x, y = tileOf(v)
	assertTrue(World.isStandable(world, x, y))
	assertEqual("settled", v.idle.phase)
	assertEqual(2, v.load.count)
end)

test("a villager already in the gather area starts settled without a path", function()
	local ctx, b = newGame()
	local t = Idle.gatherTiles(ctx, b)[1]
	local v = addVillager(ctx, t.x, t.y)
	local x0, y0 = v.x, v.y
	Session.advance(ctx, STEP)
	assertEqual("settled", v.idle.phase)
	assertTrue(Walker.idle(v.walker))
	assertEqual(x0, v.x)
	assertEqual(y0, v.y)
end)

test("with two facilities a villager gathers at the one nearest where it stands", function()
	local ctx, a = newGame()
	local req = { design = Starter.NAME, blueprint = Starter.blueprint(Builtins, Config), facing = "N", tileX = 5, tileY = 5 }
	assertTrue(Placement.fits(ctx, req))
	local other = Placement.build(ctx, req)
	local v = addVillager(ctx, other.tileX + 1, other.tileY + other.depth + 12)
	run(ctx, 30)
	local x, y = tileOf(v)
	assertTrue(inGatherArea(ctx, other, x, y), "should gather at the nearer facility")
	assertEqual(other, v.idle.facility)
	assertTrue(a ~= v.idle.facility)
end)

test("with no facility a villager walks to the nearest standable tile, or stays put on one", function()
	local world = World.new(20, 20)
	World.setTerrain(world, 10, 10, "water")
	local ctx = Session.new(world, Config, 1)
	local stuck = Session.newVillager(1, 10.5 * TILE, 10.5 * TILE, Config)
	local fine = Session.newVillager(2, 3.5 * TILE, 3.5 * TILE, Config)
	ctx.pools.villagers = { stuck, fine }
	Session.advance(ctx, STEP)
	assertTrue(Walker.idle(fine.walker), "a standable villager needs no path")
	assertFalse(Walker.idle(stuck.walker))
	run(ctx, 5)
	local x, y = tileOf(stuck)
	assertTrue(World.isStandable(world, x, y))
	assertTrue(math.abs(x - 10) <= 1 and math.abs(y - 10) <= 1)
end)

test("a job taken mid-walk clears idle state and keeps the job's path", function()
	local ctx, b = newGame()
	local p = b.ports[1]
	local v = addVillager(ctx, p.x, p.y)
	Session.advance(ctx, STEP)
	assertEqual("gathering", v.idle.phase)
	v.job = {}
	Walker.goTo(v, ctx, p.x, p.y + 8)
	local path = v.walker.path
	local last = path[#path]
	Session.advance(ctx, STEP)
	assertEqual(nil, v.idle)
	assertEqual(last, v.walker.path[#v.walker.path])
	assertEqual(p.y + 8, last.y)
end)

test("a villager with a path and no idle state finishes the path before idling", function()
	local ctx, b = newGame()
	local t = Idle.gatherTiles(ctx, b)[1]
	local v = addVillager(ctx, t.x, t.y)
	Walker.goTo(v, ctx, t.x, t.y + 3)
	Session.advance(ctx, STEP)
	assertEqual(nil, v.idle)
	assertFalse(Walker.idle(v.walker))
end)

test("the same seed gives the same gather targets", function()
	local function targets(seed)
		local ctx, b = newGame(seed)
		local out = {}
		for i = 1, 5 do
			addVillager(ctx, b.ports[1].x, b.ports[1].y)
		end
		run(ctx, 30)
		for i, v in ipairs(ctx.pools.villagers) do
			out[i] = v.x .. "," .. v.y
		end
		return table.concat(out, ";")
	end
	assertEqual(targets(7), targets(7))
end)

-- Personal space (slice 03)

local function dist(a, b)
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

local function settle(ctx, seconds)
	run(ctx, seconds or 3)
end

test("two settled villagers on one spot separate to personal space, then stop", function()
	local ctx, b = newGame()
	local t = Idle.gatherTiles(ctx, b)[1]
	local a = addVillager(ctx, t.x, t.y)
	local c = addVillager(ctx, t.x, t.y)
	run(ctx, 10)
	assertTrue(dist(a, c) >= Config.villagers.idle.personalSpace * TILE * 0.9, "not separated")
	local ax, ay, cx, cy = a.x, a.y, c.x, c.y
	run(ctx, 1)
	assertEqual(ax, a.x)
	assertEqual(ay, a.y)
	assertEqual(cx, c.x)
	assertEqual(cy, c.y)
end)

test("a busy villager passing pushes a settled one aside and keeps its path", function()
	local world = World.new(30, 30)
	local ctx = Session.new(world, Config, 1)
	ctx.pools.villagers = {}
	local idler = addVillager(ctx, 15, 15)
	idler.idle = { phase = "settled" }
	local walker = addVillager(ctx, 10, 15)
	walker.job = { busy = true }
	Walker.goTo(walker, ctx, 20, 15)
	local startY = walker.y
	local pushed = false
	for _ = 1, 600 do
		walker.idle = nil
		Session.advance(ctx, STEP)
		if math.abs(idler.y - (15.5 * TILE)) > 1 then
			pushed = true
		end
	end
	assertTrue(pushed, "settled villager never moved")
	assertEqual(startY, walker.y)
end)

test("a pushed villager is never moved onto a footprint or port tile", function()
	local ctx, b = newGame()
	for _, edge in ipairs({ { b.tileX - 1, b.tileY + 1 }, { b.ports[1].x, b.ports[1].y } }) do
		ctx.pools.villagers = {}
		local t = Idle.gatherTiles(ctx, b)[1]
		local v = addVillager(ctx, t.x, t.y)
		v.idle = { phase = "settled", facility = b }
		-- place near the edge, with a neighbour pushing toward it
		local ex, ey = edge[1], edge[2]
		local sx, sy = ex, ey
		for _, g in ipairs(Idle.gatherTiles(ctx, b)) do
			if math.abs(g.x - ex) + math.abs(g.y - ey) == 1 then
				sx, sy = g.x, g.y
				break
			end
		end
		v.x, v.y = (sx + 0.5) * TILE, (sy + 0.5) * TILE
		local n = addVillager(ctx, sx, sy)
		n.idle = { phase = "settled", facility = b }
		n.x, n.y = v.x + (sx - ex) * 2, v.y + (sy - ey) * 2
		for _ = 1, 300 do
			Session.advance(ctx, STEP)
			local x, y = tileOf(v)
			assertTrue(World.isStandable(ctx.world, x, y), "stepped on non-standable tile")
		end
	end
end)

test("a settled villager pushed past the gather radius drifts back", function()
	local ctx, b = newGame()
	local r = Config.villagers.idle.gatherRadius
	local t = Idle.gatherTiles(ctx, b)[1]
	local v = addVillager(ctx, t.x, t.y)
	v.idle = { phase = "settled", facility = b }
	v.x = (b.tileX + b.width + r + 1.5) * TILE
	v.y = (b.tileY + 1.5) * TILE
	local before = v.x
	run(ctx, 2)
	assertTrue(v.x < before, "did not drift back")
	run(ctx, 20)
	local x, y = tileOf(v)
	assertTrue(inGatherArea(ctx, b, x, y) or x <= b.tileX + b.width + r)
end)

test("a 20 villager crowd comes to rest", function()
	local ctx, b = newGame()
	local t = Idle.gatherTiles(ctx, b)[1]
	for _ = 1, 20 do
		addVillager(ctx, t.x, t.y)
	end
	local still = 0
	local rested = false
	for _ = 1, 60 * 60 do
		local before = {}
		for i, v in ipairs(ctx.pools.villagers) do
			before[i] = { v.x, v.y }
		end
		Session.advance(ctx, STEP)
		local moved = false
		for i, v in ipairs(ctx.pools.villagers) do
			if v.x ~= before[i][1] or v.y ~= before[i][2] then
				moved = true
			end
		end
		still = moved and 0 or still + 1
		if still >= 60 then
			rested = true
			break
		end
	end
	assertTrue(rested, "crowd never came to rest")
	for _, v in ipairs(ctx.pools.villagers) do
		local x, y = tileOf(v)
		assertTrue(World.isStandable(ctx.world, x, y))
	end
end)

-- Idle life (slice 04)

local function lone(seed)
	local ctx, b = newGame(seed)
	local t = Idle.gatherTiles(ctx, b)[1]
	local v = addVillager(ctx, t.x, t.y)
	return ctx, b, v
end

test("a lone settled villager turns on the spot within turnEvery[2] seconds", function()
	local ctx, b, v = lone()
	local cfg = Config.villagers.idle
	local facing = v.animator.facing
	local turned = false
	-- Turns only; stop before the earliest wander could start.
	for _ = 1, math.floor(cfg.turnEvery[2] * 60) + 5 do
		local x, y = v.x, v.y
		Session.advance(ctx, STEP)
		if v.animator.facing ~= facing then
			turned = true
			assertEqual(x, v.x)
			assertEqual(y, v.y)
			break
		end
	end
	assertTrue(turned, "never turned")
end)

test("a lone settled villager wanders within the gather area on standable tiles", function()
	local ctx, b, v = lone()
	local cfg = Config.villagers.idle
	local startX, startY = v.x, v.y
	local moved = false
	for _ = 1, math.floor((cfg.wanderEvery[2] + 3) * 60) do
		Session.advance(ctx, STEP)
		local x, y = tileOf(v)
		assertTrue(World.isStandable(ctx.world, x, y))
		assertEqual(nil, World.buildingAt(ctx.world, x, y))
		assertEqual(nil, World.portAt(ctx.world, x, y))
		if Walker.idle(v.walker) and v.idle.phase == "settled" then
			assertTrue(inGatherArea(ctx, b, x, y), "left the gather area")
		end
		if v.x ~= startX or v.y ~= startY then
			moved = true
		end
	end
	assertTrue(moved, "never wandered")
end)

test("a wander stays within wanderDistance of where it started", function()
	local ctx, b, v = lone()
	local cfg = Config.villagers.idle
	local sx, sy = v.x, v.y
	local far = 0
	for _ = 1, 60 * 60 do
		Session.advance(ctx, STEP)
		if v.idle.phase == "wandering" then
			far = math.max(far, math.sqrt((v.x - sx) ^ 2 + (v.y - sy) ^ 2))
		else
			sx, sy = v.x, v.y
		end
	end
	assertTrue(far > 0, "no wander seen")
	assertTrue(far <= (cfg.wanderDistance + 0.8) * TILE, "wandered too far")
end)

test("the same seed gives the same turn and wander sequence", function()
	local function trace(seed)
		local ctx, b = newGame(seed)
		for i = 1, 3 do
			local t = Idle.gatherTiles(ctx, b)[i * 7]
			addVillager(ctx, t.x, t.y)
		end
		local out = {}
		for step = 1, 60 * 30 do
			Session.advance(ctx, STEP)
			if step % 30 == 0 then
				for _, v in ipairs(ctx.pools.villagers) do
					out[#out + 1] = v.x .. "," .. v.y .. "," .. v.animator.facing
				end
			end
		end
		return table.concat(out, ";")
	end
	assertEqual(trace(5), trace(5))
	assertTrue(trace(5) ~= trace(6), "seeds should differ")
end)

test("a job assigned mid-wander takes over at once", function()
	local ctx, b, v = lone()
	for _ = 1, 60 * 30 do
		Session.advance(ctx, STEP)
		if v.idle.phase == "wandering" then
			break
		end
	end
	assertEqual("wandering", v.idle.phase)
	v.job = {}
	Walker.goTo(v, ctx, v.idle.facility.ports[1].x, v.idle.facility.ports[1].y)
	local last = v.walker.path[#v.walker.path]
	Session.advance(ctx, STEP)
	assertEqual(nil, v.idle)
	assertEqual(last, v.walker.path[#v.walker.path])
end)

local function placeStarter(ctx, x, y)
	return Placement.build(ctx, { design = Starter.NAME, blueprint = Starter.blueprint(Builtins, Config), facing = "N", tileX = x, tileY = y })
end

test("a lingering villager idles around its anchor, never on its footprint or ports", function()
	local ctx, storage = newGame()
	local anchor = placeStarter(ctx, 5, 5)
	-- Starts beside the storage facility, nearer to it than to the anchor.
	local v = addVillager(ctx, storage.tileX + 1, storage.tileY + storage.depth + 1)
	v.linger = { task = { kind = "operate", brick = {} }, anchor = anchor }
	run(ctx, 30)
	local x, y = tileOf(v)
	assertEqual(anchor, v.idle.facility)
	assertTrue(inGatherArea(ctx, anchor, x, y), "should gather at the anchor")
	assertEqual(nil, World.buildingAt(ctx.world, x, y))
	assertEqual(nil, World.portAt(ctx.world, x, y))
	assertTrue(v.linger ~= nil, "the linger never expires")
end)

test("when its anchor dies a lingering villager drops the linger and gathers at a storage facility", function()
	local ctx, storage = newGame()
	local anchor = placeStarter(ctx, 5, 5)
	local v = addVillager(ctx, anchor.tileX + 1, anchor.tileY + anchor.depth + 1)
	v.linger = { task = { kind = "operate", brick = {} }, anchor = anchor }
	run(ctx, 10)
	assertEqual(anchor, v.idle.facility)

	World.removeBuilding(ctx.world, anchor)
	anchor.dead = true
	run(ctx, 40)
	local x, y = tileOf(v)
	assertEqual(nil, v.linger)
	assertEqual(storage, v.idle.facility)
	assertTrue(inGatherArea(ctx, storage, x, y), "should gather at the storage facility")
end)

test("a villager lingering with a port tile idles within portReach of it, off footprint and ports", function()
	local ctx, storage = newGame()
	local anchor = placeStarter(ctx, 20, 20)
	local port = anchor.ports[1]
	local v = addVillager(ctx, storage.tileX + 1, storage.tileY + storage.depth + 1)
	v.linger = { task = { kind = "haul" }, anchor = anchor, at = { x = port.x, y = port.y } }
	run(ctx, 30)
	local x, y = tileOf(v)
	assertEqual(anchor, v.idle.facility)
	assertTrue(math.max(math.abs(x - port.x), math.abs(y - port.y)) <= Config.villagers.idle.portReach, "should wait near the port")
	assertEqual(nil, World.buildingAt(ctx.world, x, y))
	assertEqual(nil, World.portAt(ctx.world, x, y))
end)
