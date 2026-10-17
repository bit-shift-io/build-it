-- Pool system for ctx.pools.animals (docs/CONTEXT.md "Deer", "Herd") and the
-- herds they belong to (ctx.pools.herds). Deer move only through Walker and
-- Mover, so footprints, water and nodes stop them like villagers; they
-- never flee and never read intents. Pure -- no `love.*`.
--   herd = { id, tileX, tileY, cap, breed }   -- home tile; breed = seconds
--                                             -- since the herd fell under cap
--   deer = AnimalSystem.newDeer record, `herd` the herd's id, `wanderIn` the
--          seconds to its next wander (drawn from ctx.rng when first needed)
local World = require("src.game.world")
local Walker = require("src.game.components.walker")
local Animator = require("src.game.components.animator")

local AnimalSystem = {}

-- A deer record of herd `herdId` at (x, y) px, standing idle. Footprints
-- are solid to it (no mover.enter).
function AnimalSystem.newDeer(id, herdId, x, y, config)
	local cfg = config.animals.deer
	return {
		id = id,
		kind = "deer",
		herd = herdId,
		x = x,
		y = y,
		size = cfg.size,
		mover = { speed = cfg.speed },
		walker = Walker.new(),
		animator = Animator.new(),
	}
end

-- Adds a herd homed on tile (tileX, tileY) with `cap` deer; returns it.
function AnimalSystem.addHerd(ctx, tileX, tileY, cap)
	local herd = { id = #ctx.pools.herds + 1, tileX = tileX, tileY = tileY, cap = cap, breed = 0 }
	table.insert(ctx.pools.herds, herd)
	return herd
end

-- Adds a deer of `herd` standing on the centre of tile (tileX, tileY).
function AnimalSystem.spawn(ctx, herd, tileX, tileY)
	local id = ctx.nextAnimalId or 1
	ctx.nextAnimalId = id + 1
	local tile = ctx.config.tileSize
	local a = AnimalSystem.newDeer(id, herd.id, (tileX + 0.5) * tile, (tileY + 0.5) * tile, ctx.config)
	table.insert(ctx.pools.animals, a)
	return a
end

-- Standable tiles within the wander radius of the herd's home, row order.
local function homeTiles(ctx, herd)
	local r = ctx.config.animals.deer.wanderRadius
	local list = {}
	for y = herd.tileY - r, herd.tileY + r do
		for x = herd.tileX - r, herd.tileX + r do
			if (x - herd.tileX) ^ 2 + (y - herd.tileY) ^ 2 <= r * r and World.isStandable(ctx.world, x, y) then
				list[#list + 1] = { x = x, y = y }
			end
		end
	end
	return list
end

-- Hunting (docs/CONTEXT.md "Hunter"): an operator reserves a deer by setting
-- `deer.hunter` (a runtime-only mark, never saved); a reserved deer stands
-- still. Killing marks it dead; the despawn sweep removes it.
function AnimalSystem.isFree(deer)
	return not deer.dead and deer.hunter == nil
end

function AnimalSystem.reserve(deer, hunter)
	deer.hunter = hunter
end

function AnimalSystem.release(deer)
	deer.hunter = nil
end

function AnimalSystem.kill(deer)
	deer.dead = true
	deer.hunter = nil
end

-- One deer's step: count down to a wander, walk, animate.
local function move(a, herd, ctx)
	local cfg = ctx.config.animals.deer
	local fromX, fromY = a.x, a.y
	if a.hunter then
		a.walker.path = {}
	elseif Walker.idle(a.walker) then
		a.wanderIn = (a.wanderIn or ctx.rng:range(cfg.wanderEvery[1], cfg.wanderEvery[2])) - ctx.dt
		if a.wanderIn <= 0 then
			a.wanderIn = nil
			local tiles = homeTiles(ctx, herd)
			if #tiles > 0 then
				local t = tiles[ctx.rng:int(1, #tiles)]
				Walker.goTo(a, ctx, t.x, t.y)
			end
		end
	end
	Walker.step(a, ctx)
	Animator.update(a.animator, a.x - fromX, a.y - fromY, ctx.config.character)
end

-- A herd under its cap adds one deer on a free standable tile near home
-- every breedEvery seconds; at its cap the timer rests.
local function breed(ctx, herd, count)
	if count >= herd.cap then
		herd.breed = 0
		return
	end
	herd.breed = herd.breed + ctx.dt
	if herd.breed < ctx.config.animals.deer.breedEvery then
		return
	end
	local tile = ctx.config.tileSize
	local taken = {}
	for _, a in ipairs(ctx.pools.animals) do
		taken[math.floor(a.y / tile) * ctx.world.width + math.floor(a.x / tile)] = true
	end
	local free = {}
	for _, t in ipairs(homeTiles(ctx, herd)) do
		if not taken[t.y * ctx.world.width + t.x] then
			free[#free + 1] = t
		end
	end
	if #free > 0 then
		local t = free[ctx.rng:int(1, #free)]
		AnimalSystem.spawn(ctx, herd, t.x, t.y)
		herd.breed = 0
	end
end

function AnimalSystem.update(ctx)
	local counts = {}
	for _, a in ipairs(ctx.pools.animals) do
		if not a.dead then
			counts[a.herd] = (counts[a.herd] or 0) + 1
			move(a, ctx.pools.herds[a.herd], ctx)
		end
	end
	for _, herd in ipairs(ctx.pools.herds) do
		breed(ctx, herd, counts[herd.id] or 0)
	end
end

-- Despawn sweep: dead deer leave the pool.
function AnimalSystem.despawn(ctx)
	local pool = ctx.pools.animals
	for i = #pool, 1, -1 do
		if pool[i].dead then
			table.remove(pool, i)
		end
	end
end

return AnimalSystem
