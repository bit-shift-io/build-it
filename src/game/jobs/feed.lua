-- A feed job (docs/CONTEXT.md "Feed job", "Collapse"): one free villager
-- carries a meal from a store to a collapsed villager, who eats it on
-- delivery. Steps: walk to the food, pick the meal up, walk to the collapsed
-- villager, hand it over. Plain data in ctx.pools.jobs;
-- src/game/systems/job_system.lua creates, assigns and steps it. Pure -- no
-- `love.*`.
--
--   job = { kind = "feed", source = <endpoint>, target = <villager>,
--           plan = { item, ... }, carried = { item, ... },
--           villager = <villager> | nil, stage = "toFood"|"toTarget",
--           dead = true when ended }
--   endpoint = { building, store = <Storage>, x, y } (as in haul.lua)
--
-- From creation the job reserves every item of its plan at the source and
-- marks the target (`target.feeder`), so only one feeder goes per collapsed
-- villager. Pick-up moves the plan into `carried`; ending the job releases
-- what is still reserved and puts what is still carried back.
local Storage = require("src.game.components.storage")
local Walker = require("src.game.components.walker")
local Eat = require("src.game.jobs.eat")

local Feed = {}

-- A new open feed job for collapsed villager `target` from `source`, nil when
-- the source holds no food to reserve. Reserves the meal and the target.
function Feed.new(source, target, cfg)
	local plan = Eat.plan(function(item)
		return Storage.available(source.store, item)
	end, target.needs.hunger, cfg)
	if #plan == 0 then
		return nil
	end
	for _, item in ipairs(plan) do
		Storage.reserve(source.store, item, 1)
	end
	local job = { kind = "feed", source = source, target = target, plan = plan, carried = {}, stage = "toFood" }
	target.feeder = job
	return job
end

-- Whether collapsed villager `target` already has a feeder on the way.
function Feed.fed(target)
	return target.feeder ~= nil and not target.feeder.dead
end

-- Ends `job`: releases what it still reserves, puts back what it still
-- carries, frees its villager and its target.
function Feed.finish(job)
	if job.dead then
		return
	end
	for _, item in ipairs(job.plan) do
		Storage.unreserve(job.source.store, item, 1)
	end
	for _, item in ipairs(job.carried) do
		Storage.add(job.source.store, item)
	end
	job.plan, job.carried = {}, {}
	job.dead = true
	if job.target.feeder == job then
		job.target.feeder = nil
	end
	if job.villager then
		job.villager.job = nil
	end
end

local function walkTo(job, ctx, x, y)
	if not Walker.goTo(job.villager, ctx, x, y) then
		Feed.finish(job)
		return false
	end
	return true
end

-- Gives `job` to villager `v` and sends it to the food. False (and the job
-- ended) when there is no route.
function Feed.start(job, v, ctx)
	job.villager = v
	v.job = job
	return walkTo(job, ctx, job.source.x, job.source.y)
end

local function pickUp(job, ctx)
	local store = job.source.store
	for _, item in ipairs(job.plan) do
		Storage.unreserve(store, item, 1)
		Storage.remove(store, item)
		job.carried[#job.carried + 1] = item
	end
	job.plan = {}
	job.stage = "toTarget"
	local tile = ctx.config.tileSize
	walkTo(job, ctx, math.floor(job.target.x / tile), math.floor(job.target.y / tile))
end

local function deliver(job, ctx)
	local needs = job.target.needs
	for _, item in ipairs(job.carried) do
		needs.hunger = math.max(0, needs.hunger - ctx.config.food[item].fill)
	end
	job.carried = {}
	Feed.finish(job)
end

-- One step, after the villager walked: ends the job when the food's building
-- is gone while it is still to be fetched, or the target got up; on arrival
-- picks the meal up or hands it over.
function Feed.step(job, ctx)
	if job.dead then
		return
	end
	if (job.stage == "toFood" and job.source.building.dead) or Walker.failed(job.villager.walker) or job.target.needs.health > 0 then
		return Feed.finish(job)
	end
	if not Walker.idle(job.villager.walker) then
		return
	end
	if job.stage == "toFood" then
		pickUp(job, ctx)
	else
		deliver(job, ctx)
	end
end

return Feed
