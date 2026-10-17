-- A haul job (docs/CONTEXT.md "Haul job"): one villager carries one load of
-- one item from a source store to a destination store, then the job ends.
-- Steps: walk to the source, pick up, walk to the destination, drop. A job
-- with no source starts with the villager already carrying the load.
-- Plain data in ctx.pools.jobs; src/game/systems/job_system.lua creates,
-- assigns and steps it. Pure -- no `love.*`.
--
--   job = { kind = "haul", item, count,
--           source = <endpoint> | nil, dest = <endpoint>,
--           villager = <villager> | nil,
--           stage = "toSource"|"toDest", dead = true when ended }
--   endpoint = { building, store = <Storage>, x, y, claim? } -- (x, y): the
--              tile the villager stands on to pick up or drop; a source
--              with a `claim` (StorageFacility.claim's) takes a construction
--              site's claimed items, and its destination is that site
--              (building = the site, store = site.delivered)
--
-- From creation the job reserves `count` of the item at the source (for a
-- claim: counts it in claim.taking, the claim already holds the items) and
-- `count` room at the destination; pick-up releases the first, the drop
-- (or any failure) the second.
local Storage = require("src.game.components.storage")
local Load = require("src.game.components.load")
local Walker = require("src.game.components.walker")

local Haul = {}

-- A new open haul job moving `count` of `item` from `source` (nil when
-- the villager already carries it) to `dest`; reserves both ends.
function Haul.new(item, count, source, dest)
	if source and source.claim then
		source.claim.taking = source.claim.taking + count
	elseif source then
		Storage.reserve(source.store, item, count)
	end
	Storage.reserveRoom(dest.store, count)
	return { kind = "haul", item = item, count = count, source = source, dest = dest, stage = source and "toSource" or "toDest" }
end

local function releaseSource(job)
	if job.source and job.stage == "toSource" then
		local claim = job.source.claim
		if claim then
			claim.taking = claim.taking - job.count
		else
			Storage.unreserve(job.source.store, job.item, job.count)
		end
	end
end

-- Ends `job`: releases what it still reserves and frees its villager,
-- who keeps whatever it carries.
function Haul.finish(job)
	if job.dead then
		return
	end
	releaseSource(job)
	Storage.releaseRoom(job.dest.store, job.count)
	job.dead = true
	if job.villager then
		job.villager.job = nil
	end
end

local function walkTo(job, ctx, point)
	if not Walker.goTo(job.villager, ctx, point.x, point.y) then
		Haul.finish(job)
		return false
	end
	return true
end

-- Gives `job` to villager `v` and sends it off. False (and the job ended)
-- when there is no route.
function Haul.start(job, v, ctx)
	job.villager = v
	v.job = job
	return walkTo(job, ctx, job.stage == "toSource" and job.source or job.dest)
end

-- Takes `n` of a claim out of the claim, and the claim off its site once
-- it is all picked up.
local function takeClaimed(job, store, n)
	local claim, site = job.source.claim, job.dest.building
	Storage.unclaim(store, job.item, n)
	claim.count = claim.count - n
	if claim.count == 0 then
		for i, c in ipairs(site.claims) do
			if c == claim then
				table.remove(site.claims, i)
				break
			end
		end
	end
end

-- How many of the job's item it may pick up: what is neither reserved nor
-- claimed, or for a claim, the claimed items no other job reserved.
local function takeable(job, store)
	local claim = job.source.claim
	if not claim then
		return Storage.available(store, job.item)
	end
	local reserved = store.reserved and store.reserved[job.item] or 0
	return math.min(claim.count, (store.counts[job.item] or 0) - reserved)
end

local function pickUp(job, ctx)
	local store, load = job.source.store, job.villager.load
	releaseSource(job)
	job.stage = "toDest"
	local n = math.max(0, math.min(job.count, takeable(job, store), Load.room(load)))
	for _ = 1, n do
		Storage.remove(store, job.item)
	end
	if job.source.claim and n > 0 then
		takeClaimed(job, store, n)
	end
	Load.add(load, job.item, n)
	if n == 0 then
		return Haul.finish(job)
	end
	walkTo(job, ctx, job.dest)
end

local function drop(job)
	local store, load = job.dest.store, job.villager.load
	Storage.releaseRoom(store, job.count)
	job.count = 0
	local n = load.item == job.item and math.min(load.count, Storage.room(store)) or 0
	for _ = 1, n do
		Storage.add(store, job.item)
	end
	Load.remove(load, n)
	local xp = job.villager.xp
	xp.haul = (xp.haul or 0) + 1
	Haul.finish(job)
	local source = job.source
	if source and not source.building.dead then
		-- Lingers beside the source's port (docs/CONTEXT.md "Linger spot"): the
		-- same route next time comes to this villager first.
		job.villager.linger = {
			task = { kind = "haul", item = job.item, source = source.building, dest = job.dest.building },
			anchor = source.building,
			at = { x = source.x, y = source.y },
		}
	end
end

-- One step, after the villager walked: ends the job when an end's
-- building is gone; on arrival picks up or drops.
function Haul.step(job, ctx)
	if job.dead then
		return
	end
	if job.dest.building.dead or (job.stage == "toSource" and job.source.building.dead) then
		return Haul.finish(job)
	end
	if Walker.failed(job.villager.walker) then
		return Haul.finish(job)
	end
	if not Walker.idle(job.villager.walker) then
		return
	end
	if job.stage == "toSource" then
		pickUp(job, ctx)
	else
		drop(job)
	end
end

return Haul
