-- Idle state of a free villager (docs/CONTEXT.md "Free villager", "Gather
-- area", "Linger spot"), on the villager record: `v.idle = { phase, facility }`.
-- `facility` is the anchor building whose gather area it idles in: the
-- building it lingers at (`v.linger.anchor`), else the nearest storage
-- facility.
--   gathering: walking to its picked tile in the gather area
--   settled:   arrived (or already there); stays put, now and then turns
--              (`turnTo`, a facing the villager system applies) or wanders;
--              on a tile that is no longer standable it gathers again
--   wandering: walking a short way to another gather tile, then settled
-- Idle state exists only while `v.job` is nil. Pure -- no `love.*`.
local World = require("src.game.world")
local Walker = require("src.game.components.walker")
local StorageFacility = require("src.game.components.storage_facility")
local Character = require("src.game.props.character")

local Idle = {}

local function tileOf(v, tile)
	return math.floor(v.x / tile), math.floor(v.y / tile)
end

-- Tiles from tile (x, y) to facility b's footprint (0 inside it).
local function footprintDistance(b, x, y)
	local dx = math.max(b.tileX - x, 0, x - (b.tileX + b.width - 1))
	local dy = math.max(b.tileY - y, 0, y - (b.tileY + b.depth - 1))
	return dx, dy
end

local function nearestFacility(ctx, x, y)
	local best, bestD
	for _, b in ipairs(StorageFacility.all(ctx)) do
		local dx, dy = footprintDistance(b, x, y)
		local d = dx * dx + dy * dy
		if not bestD or d < bestD then
			best, bestD = b, d
		end
	end
	return best
end

Idle.nearestFacility = nearestFacility

-- The building `v` idles around from tile (x, y): its linger anchor while
-- that stands (a dead anchor drops the linger), else the nearest storage
-- facility.
local function anchorFor(v, ctx, x, y)
	if v.linger and v.linger.anchor.dead then
		v.linger = nil
	end
	return v.linger and v.linger.anchor or nearestFacility(ctx, x, y)
end

-- Standable tiles of facility b's gather area, in row order. With `at`
-- (a tile {x, y}), only those within portReach of it, when there are any.
function Idle.gatherTiles(ctx, b, at)
	local cfg, world = ctx.config.villagers.idle, ctx.world
	local r = cfg.gatherRadius
	local list = {}
	for y = math.max(0, b.tileY - r), math.min(world.height - 1, b.tileY + b.depth + r - 1) do
		for x = math.max(0, b.tileX - r), math.min(world.width - 1, b.tileX + b.width + r - 1) do
			local dx, dy = footprintDistance(b, x, y)
			local d = math.max(dx, dy)
			if d >= cfg.gatherMin and d <= r and World.isStandable(world, x, y) then
				list[#list + 1] = { x = x, y = y }
			end
		end
	end
	if at then
		local near = {}
		for _, t in ipairs(list) do
			if math.max(math.abs(t.x - at.x), math.abs(t.y - at.y)) <= cfg.portReach then
				near[#near + 1] = t
			end
		end
		if #near > 0 then
			return near
		end
	end
	return list
end

-- The standable tile nearest (x, y), ring by ring; nil when none.
local function nearestStandable(world, x, y)
	local reach = math.max(world.width, world.height)
	for r = 0, reach do
		local best, bestD
		for ty = y - r, y + r do
			for tx = x - r, x + r do
				if math.max(math.abs(tx - x), math.abs(ty - y)) == r and World.isStandable(world, tx, ty) then
					local d = (tx - x) ^ 2 + (ty - y) ^ 2
					if not bestD or d < bestD then
						best, bestD = { x = tx, y = ty }, d
					end
				end
			end
		end
		if best then
			return best
		end
	end
end

local function start(v, ctx)
	local tile = ctx.config.tileSize
	local x, y = tileOf(v, tile)
	local facility = anchorFor(v, ctx, x, y)
	local idle = { phase = "settled", facility = facility, at = v.linger and v.linger.at }
	v.idle = idle
	local target
	if facility then
		local tiles = Idle.gatherTiles(ctx, facility, idle.at)
		for _, t in ipairs(tiles) do
			if t.x == x and t.y == y then
				return
			end
		end
		if #tiles > 0 then
			target = tiles[ctx.rng:int(1, #tiles)]
		end
	elseif not World.isStandable(ctx.world, x, y) then
		target = nearestStandable(ctx.world, x, y)
	end
	if target and Walker.goTo(v, ctx, target.x, target.y) then
		idle.phase = "gathering"
	end
end

-- Timers for a settled villager, drawn from ctx.rng when first needed: a
-- turn to a random other facing on the spot, and a short wander to another
-- standable gather tile within wanderDistance. A wander is a walker path,
-- so crowd mates never nudge it and it cannot oscillate; the villager
-- settles on arrival and personal space takes over again.
local function life(v, ctx)
	local cfg, idle = ctx.config.villagers.idle, v.idle
	idle.turnIn = idle.turnIn or ctx.rng:range(cfg.turnEvery[1], cfg.turnEvery[2])
	idle.wanderIn = idle.wanderIn or ctx.rng:range(cfg.wanderEvery[1], cfg.wanderEvery[2])
	idle.turnIn = idle.turnIn - ctx.dt
	idle.wanderIn = idle.wanderIn - ctx.dt
	if idle.wanderIn <= 0 then
		idle.wanderIn = nil
		if idle.facility then
			local tile = ctx.config.tileSize
			local x, y = tileOf(v, tile)
			local near = {}
			for _, t in ipairs(Idle.gatherTiles(ctx, idle.facility, idle.at)) do
				local d = math.sqrt((t.x - x) ^ 2 + (t.y - y) ^ 2)
				if d > 0 and d <= cfg.wanderDistance then
					near[#near + 1] = t
				end
			end
			if #near > 0 then
				local t = near[ctx.rng:int(1, #near)]
				if Walker.goTo(v, ctx, t.x, t.y) then
					idle.phase = "wandering"
					return
				end
			end
		end
	end
	if idle.turnIn <= 0 then
		idle.turnIn = nil
		local count = #Character.DIRECTIONS
		local pick = ctx.rng:int(1, count - 1)
		idle.turnTo = pick >= v.animator.facing and pick + 1 or pick
	end
end

-- One step of idle logic for villager `v`, before Walker.step. A job
-- clears the idle state at once and the job owns the path.
function Idle.update(v, ctx)
	if v.idle then
		v.idle.turnTo = nil
	end
	if v.job then
		v.idle = nil
		return
	end
	-- The building it idles around is gone: gather again once it stands still.
	if v.idle and v.idle.facility and v.idle.facility.dead then
		v.idle = nil
	end
	if v.idle == nil then
		-- A villager still on a path (e.g. after a load) finishes it first.
		if Walker.idle(v.walker) then
			start(v, ctx)
		end
	elseif v.idle.phase ~= "settled" and Walker.idle(v.walker) then
		v.idle.phase = "settled"
	elseif v.idle.phase == "settled" and Walker.idle(v.walker) then
		-- A footprint placed on it, or a job that ended inside one: walk out.
		local x, y = tileOf(v, ctx.config.tileSize)
		if World.isStandable(ctx.world, x, y) then
			life(v, ctx)
		else
			start(v, ctx)
		end
	end
end

-- Drift intent for a settled villager: away from every villager and the
-- player inside personal space (weight grows as they get closer), plus a
-- soft pull toward its facility once outside the gather radius. Returns
-- x, y with length <= 1, or 0, 0 when there is nothing to do or the push is
-- inside the dead zone. A step onto a non-standable tile is dropped per
-- axis, so a villager never ends up on a footprint, port or water.
function Idle.steer(v, ctx)
	local idle = v.idle
	if not (idle and idle.phase == "settled" and not v.job and Walker.idle(v.walker)) then
		return 0, 0
	end
	local cfg, tile = ctx.config.villagers.idle, ctx.config.tileSize
	local space = cfg.personalSpace * tile
	local ix, iy = 0, 0
	local function push(o)
		if o == v then
			return
		end
		local dx, dy = v.x - o.x, v.y - o.y
		if math.abs(dx) >= space or math.abs(dy) >= space then
			return
		end
		local d = math.sqrt(dx * dx + dy * dy)
		if d >= space then
			return
		end
		if d < 1e-6 then
			local a = ctx.rng:next() * 2 * math.pi
			dx, dy, d = math.cos(a), math.sin(a), 1
		end
		local w = 1 - d / space
		ix, iy = ix + dx / d * w, iy + dy / d * w
	end
	for _, o in ipairs(ctx.pools.villagers) do
		push(o)
	end
	for _, o in ipairs(ctx.pools.characters) do
		push(o)
	end
	local b = idle.facility
	if b then
		-- Pull grows with how far (in tiles) the villager is outside the
		-- gather area's rectangle, so it never switches on and off at the edge.
		local r = cfg.gatherRadius
		local function pull(p, lo, hi)
			if p < lo * tile then
				return math.min(1, (lo * tile - p) / tile) * cfg.pullBack
			elseif p > hi * tile then
				return -math.min(1, (p - hi * tile) / tile) * cfg.pullBack
			end
			return 0
		end
		ix = ix + pull(v.x, b.tileX - r, b.tileX + b.width + r)
		iy = iy + pull(v.y, b.tileY - r, b.tileY + b.depth + r)
	end
	-- Drop a push axis whose next step would put the villager's body on a
	-- non-standable tile: it slides along the edge instead of nudging
	-- against it.
	local look = v.size / 2 + 1
	local function blocked(sx, sy)
		local x, y = math.floor((v.x + sx * look) / tile), math.floor((v.y + sy * look) / tile)
		return not World.isStandable(ctx.world, x, y)
	end
	if ix ~= 0 and blocked(ix > 0 and 1 or -1, 0) then
		ix = 0
	end
	if iy ~= 0 and blocked(0, iy > 0 and 1 or -1) then
		iy = 0
	end
	local m = math.sqrt(ix * ix + iy * iy)
	-- Hysteresis: a villager at rest needs a push wakeFactor times the dead
	-- zone to move again, so neighbours do not trade nudges forever.
	if m < (idle.resting and cfg.deadZone * cfg.wakeFactor or cfg.deadZone) then
		idle.resting = true
		return 0, 0
	end
	idle.resting = false
	if m > 1 then
		ix, iy = ix / m, iy / m
	end
	return ix, iy
end

return Idle
