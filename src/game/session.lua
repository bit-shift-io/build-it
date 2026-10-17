-- A running game session: builds ctx and owns the single frame-order
-- function, Session.step (docs/ARCHITECTURE.md "Systems and frame order").
-- Pure -- no `love.*`; runs under plain LuaJIT.
local Rng = require("src.core.rng")
local World = require("src.game.world")
local CharacterSystem = require("src.game.systems.character_system")
local NodeSystem = require("src.game.systems.node_system")
local BuildingSystem = require("src.game.systems.building_system")
local VillagerSystem = require("src.game.systems.villager_system")
local JobSystem = require("src.game.systems.job_system")
local AnimalSystem = require("src.game.systems.animal_system")
local Walker = require("src.game.components.walker")
local Load = require("src.game.components.load")
local Inventory = require("src.game.components.inventory")
local Animator = require("src.game.components.animator")
local Needs = require("src.game.components.needs")
local Storage = require("src.game.components.storage")
local Placement = require("src.game.buildings.placement")
local Starter = require("src.game.designs.starter")

local Session = {}

-- A name from config.names, picked with ctx.rng.
local function pickName(ctx)
	local names = ctx.config.names
	return names[ctx.rng:int(1, #names)]
end

local function newCharacter(id, player, x, y, config)
	return {
		id = id,
		player = player,
		x = x,
		y = y,
		size = config.character.size,
		mover = { speed = config.character.speed },
		inventory = Inventory.new(),
		harvester = { progress = 0 },
		needs = Needs.new(),
		animator = Animator.new(),
	}
end

-- A villager record (docs/CONTEXT.md "Villager") at (x, y) px, standing
-- idle and empty-handed (load). Footprints are solid to it unless it
-- operates a brick there (mover.enter, set by src/game/jobs/operate.lua).
-- `job` is the job it holds, nil while free.
function Session.newVillager(id, x, y, config)
	local cfg = config.villagers
	return {
		id = id,
		x = x,
		y = y,
		size = cfg.size,
		mover = { speed = cfg.speed },
		walker = Walker.new(),
		load = Load.new(config),
		xp = {},
		needs = Needs.new(),
		animator = Animator.new(),
	}
end

-- world: a world table (src/game/world.lua), literal or from
-- src/game/world_gen.lua. seed fixes ctx.rng. The world's node pool is
-- ctx.pools.nodes (the same table).
function Session.new(world, config, seed)
	local ctx = {
		dt = 0,
		time = 0,
		world = world,
		config = config,
		seed = seed,
		rng = Rng.new(seed),
		intents = {},
		pools = { characters = {}, nodes = world.nodes or {}, buildings = {}, sites = {}, villagers = {}, jobs = {}, animals = {}, herds = {} },
	}
	local cx, cy = World.center(world, config)
	local player = newCharacter(1, 1, cx, cy, config)
	player.name = pickName(ctx)
	table.insert(ctx.pools.characters, player)
	return ctx
end

-- Puts config.villagers.count villagers on the centres of distinct open
-- tiles within spawnRadius tiles of building b's footprint: never on a
-- port tile or the player's tile. ctx.rng picks the tiles from the
-- candidates in row order, so the same seed spawns the same villagers.
local function spawnVillagers(ctx, b, player)
	local config, world = ctx.config, ctx.world
	local tile, r = config.tileSize, config.villagers.spawnRadius
	local px, py = math.floor(player.x / tile), math.floor(player.y / tile)
	local free = {}
	for y = math.max(0, b.tileY - r), math.min(world.height - 1, b.tileY + b.depth + r - 1) do
		for x = math.max(0, b.tileX - r), math.min(world.width - 1, b.tileX + b.width + r - 1) do
			if not World.isBlocked(world, x, y) and not World.portAt(world, x, y) and not (x == px and y == py) then
				free[#free + 1] = { x = x, y = y }
			end
		end
	end
	local count = config.villagers.count
	assert(#free >= count, "no room for the villagers around the storage facility")
	for id = 1, count do
		local k = ctx.rng:int(id, #free)
		free[id], free[k] = free[k], free[id]
		local t = free[id]
		local v = Session.newVillager(id, (t.x + 0.5) * tile, (t.y + 0.5) * tile, config)
		v.name = pickName(ctx)
		table.insert(ctx.pools.villagers, v)
	end
end

-- A herd record and its deer for each of the generated world's herds
-- (world.herds, src/game/world_gen.lua).
local function spawnHerds(ctx)
	for _, h in ipairs(ctx.world.herds or {}) do
		local herd = AnimalSystem.addHerd(ctx, h.tileX, h.tileY, h.cap)
		for _, t in ipairs(h.deer) do
			AnimalSystem.spawn(ctx, herd, t.x, t.y)
		end
	end
end

-- A new game on `world` (src/game/world_gen.lua's): Session.new, plus the
-- free starting storage facility (src/game/designs/starter.lua) facing N
-- with its footprint centred on the world's centre tile, the stockpile
-- (config.stockpile) in its storage, the player moved to the tile just
-- south of its middle port tile, so it starts outside the footprint, and
-- the villagers around it (spawnVillagers), and the deer herds (spawnHerds).
function Session.newGame(world, config, seed)
	local ctx = Session.new(world, config, seed)
	local design = Starter.design(config)
	local version = design.versions[1]
	local request = {
		design = design,
		version = 1,
		facing = "N",
		tileX = math.floor(world.width / 2) - math.floor(version.width / 2),
		tileY = math.floor(world.height / 2) - math.floor(version.depth / 2),
	}
	assert(Placement.fits(ctx, request))
	local b = Placement.build(ctx, request)
	local items = {}
	for item in pairs(config.stockpile) do
		items[#items + 1] = item
	end
	table.sort(items)
	for _, item in ipairs(items) do
		for _ = 1, config.stockpile[item] do
			Storage.add(b.storage, item)
		end
	end
	local c = ctx.pools.characters[1]
	c.x = (request.tileX + math.floor(b.width / 2) + 0.5) * config.tileSize
	c.y = (request.tileY + b.depth + 1.5) * config.tileSize
	spawnVillagers(ctx, b, c)
	spawnHerds(ctx)
	return ctx
end

-- The whole frame order, in one place. ctx.dt must already be set.
--   1. Intents: `app` (or a test) fills ctx.intents[player] before the step.
--   2. Characters: walk, then hand-harvest.
--   2a. Villagers: walk their paths (no intents; they never read them).
--   2b. Growth: saplings age, so a tree turns harvestable before any brick
--      looks for one.
--   3. Reservations: dead nodes release their function bricks, before any
--      brick picks a new target.
--   4. Buildings: place the construction sites players asked for
--      (intent.place), turn built sites into buildings, then run their
--      function bricks and fill their outputs.
--   4a. Jobs: free villagers take new haul jobs, then every job steps
--      (pick up or drop on arrival). After the buildings, so haulers read
--      output buffers after Ports.flush, and jobs see buildings marked
--      dead this step.
--   4b. Animals: deer wander near their herd's home, and a herd under its
--      cap breeds. They use the walker, so footprints and water hold.
--   5. Despawn sweeps (last): ended jobs leave the pool, removed buildings
--      release their nodes and leave theirs, built sites leave theirs, then
--      depleted nodes leave theirs. Nothing is ever removed mid-iteration.
function Session.step(ctx)
	CharacterSystem.update(ctx)
	VillagerSystem.update(ctx)
	NodeSystem.grow(ctx)
	NodeSystem.refill(ctx)
	NodeSystem.releaseDead(ctx)
	BuildingSystem.update(ctx)
	JobSystem.update(ctx)
	AnimalSystem.update(ctx)
	JobSystem.despawn(ctx)
	BuildingSystem.despawn(ctx)
	NodeSystem.despawn(ctx)
	AnimalSystem.despawn(ctx)
end

-- One fixed step: `app` accumulates real time and calls this every 1/60 s.
function Session.advance(ctx, dt)
	ctx.dt = dt
	ctx.time = ctx.time + dt
	Session.step(ctx)
end

return Session
