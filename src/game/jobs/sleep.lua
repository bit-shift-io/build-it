-- The sleep job (docs/CONTEXT.md "Bed", "Tiredness"): a tired villager
-- sleeps until its tiredness reaches 0. With a free bed it reserves the
-- nearest one, walks into the bed's building through a doorway
-- (`mover.enter`, as an operator does) and sleeps beside it; with none it sleeps where it stands, at the slower
-- ground rate. A bed is the exception to ADR 0003: it needs no operator, so
-- the brick's `occupant` is the sleep job, not an operator job. Plain data
-- in ctx.pools.jobs; src/game/systems/job_system.lua creates, assigns and
-- steps it. Pure -- no `love.*`.
--
--   job = { kind = "sleep", building = <building> | nil, brick = <bed record>
--           | nil, villager = <villager> | nil, stage = "toBed"|"sleeping",
--           rate = <tiredness lost per second> | nil, dead = true when ended }
--
-- Nil `building` and `brick` mean sleeping rough. Hunger still rises while
-- asleep (src/game/systems/villager_system.lua applies Sleep.rate).
local Walker = require("src.game.components.walker")

local Sleep = {}

local function tiles(ax, ay, bx, by)
	return math.max(math.abs(ax - bx), math.abs(ay - by))
end

-- The free bed nearest tile (x, y) as `building, brick`; ties go to the
-- first in pool order. Nil when none is free.
function Sleep.nearestBed(ctx, x, y)
	local best, bestFb, bestD
	for _, b in ipairs(ctx.pools.buildings) do
		if not b.dead then
			for _, fb in ipairs(b.functionBricks) do
				if fb.bed and not fb.occupant then
					local d = tiles(fb.tileX, fb.tileY, x, y)
					if not bestD or d < bestD then
						best, bestFb, bestD = b, fb, d
					end
				end
			end
		end
	end
	return best, bestFb
end

-- A new open sleep job for bed `fb` of `building`, reserving it; with no
-- bed, one that sleeps rough.
function Sleep.new(building, fb)
	local job = { kind = "sleep", building = building, brick = fb, stage = "toBed" }
	if fb then
		fb.occupant = job
	end
	return job
end

-- Ends `job`: the villager wakes and may walk out of the bed's building,
-- the bed is free again.
function Sleep.finish(job)
	if job.dead then
		return
	end
	job.dead = true
	if job.brick then
		job.brick.occupant = nil
	end
	if job.villager then
		job.villager.job = nil
		job.villager.mover.enter = nil
	end
end

-- Falls asleep where it stands: the bed is let go (if any).
local function sleepRough(job, ctx)
	if job.brick then
		job.brick.occupant = nil
	end
	job.building, job.brick = nil, nil
	job.villager.mover.enter = nil
	job.villager.walker.path = {}
	job.stage, job.rate = "sleeping", ctx.config.needs.groundRestRate
end

-- Gives `job` to villager `v`. With no route to the bed it sleeps rough.
function Sleep.start(job, v, ctx)
	job.villager = v
	v.job = job
	v.linger = nil
	if not job.brick then
		return sleepRough(job, ctx)
	end
	v.mover.enter = job.building
	if not Walker.goInside(v, ctx, job.building, job.brick.pointX, job.brick.pointY) then
		sleepRough(job, ctx)
	end
end

-- Tiredness lost per second by villager `v` this step: its job's rate while
-- asleep, else nil.
function Sleep.rate(v)
	local job = v.job
	return job and job.kind == "sleep" and job.stage == "sleeping" and job.rate or nil
end

-- One step, after the villager walked: wakes it when its bed's building is
-- gone; on arrival it sleeps until tiredness is 0.
function Sleep.step(job, ctx)
	if job.dead then
		return
	end
	local v = job.villager
	if job.building and job.building.dead then
		return Sleep.finish(job)
	end
	if job.stage == "toBed" then
		if Walker.failed(v.walker) then
			return sleepRough(job, ctx)
		end
		if not Walker.idle(v.walker) then
			return
		end
		job.stage, job.rate = "sleeping", ctx.config.needs.bedRestRate
	end
	if v.needs.tiredness <= 0 then
		Sleep.finish(job)
	end
end

return Sleep
