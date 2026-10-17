-- Meals and the eat job (docs/CONTEXT.md "Meal", "Food", "Feed job"). A meal
-- eats one item at a time, highest fill first, until hunger reaches 0. An
-- eat job walks a hungry villager to a storage facility's output port tile,
-- eats a meal there, then ends. Plain data in ctx.pools.jobs;
-- src/game/systems/job_system.lua creates, assigns and steps it. Pure -- no
-- `love.*`.
--
--   job = { kind = "eat", source = <endpoint>, plan = { item, ... },
--           villager = <villager> | nil, stage = "toFood"|"eating",
--           timer, dead = true when ended }
--   endpoint = { building, store = <Storage>, x, y } (as in haul.lua)
--
-- From creation the job reserves every item of its plan at the source
-- (Storage.reserve), so no other villager or job counts them. Each item is
-- taken out of the store as it is eaten; ending the job releases the rest.
local Storage = require("src.game.components.storage")
local Walker = require("src.game.components.walker")

local Eat = {}

-- Hunger below this counts as gone, so float rounding never costs an extra
-- item.
local EPS = 0.001

local function foods(cfg)
	local list = {}
	for item in pairs(cfg) do
		list[#list + 1] = item
	end
	table.sort(list, function(a, b)
		if cfg[a].fill ~= cfg[b].fill then
			return cfg[a].fill > cfg[b].fill
		end
		return a < b
	end)
	return list
end

-- The items of one meal for `hunger` (0..1): highest fill first, one at a
-- time, until hunger reaches 0 or the food runs out. `count(item)` is how
-- many of an item may be eaten; `cfg` is config.food.
function Eat.plan(count, hunger, cfg)
	local plan = {}
	for _, item in ipairs(foods(cfg)) do
		for _ = 1, count(item) do
			if hunger <= EPS then
				return plan
			end
			plan[#plan + 1] = item
			hunger = hunger - cfg[item].fill
		end
	end
	return plan
end

-- A new open eat job for `hunger` at `source`, nil when the source holds no
-- food to reserve. Reserves the meal.
function Eat.new(source, hunger, cfg)
	local plan = Eat.plan(function(item)
		return Storage.available(source.store, item)
	end, hunger, cfg)
	if #plan == 0 then
		return nil
	end
	for _, item in ipairs(plan) do
		Storage.reserve(source.store, item, 1)
	end
	return { kind = "eat", source = source, plan = plan, stage = "toFood", timer = 0 }
end

-- Ends `job`: releases what it still reserves and frees its villager.
function Eat.finish(job)
	if job.dead then
		return
	end
	for _, item in ipairs(job.plan) do
		Storage.unreserve(job.source.store, item, 1)
	end
	job.plan = {}
	job.dead = true
	if job.villager then
		job.villager.job = nil
	end
end

-- Gives `job` to villager `v` and sends it off. False (and the job ended)
-- when there is no route.
function Eat.start(job, v, ctx)
	job.villager = v
	v.job = job
	if not Walker.goTo(v, ctx, job.source.x, job.source.y) then
		Eat.finish(job)
		return false
	end
	return true
end

-- Eats the next item of the plan.
local function eatOne(job, ctx)
	local needs, store = job.villager.needs, job.source.store
	local item = table.remove(job.plan, 1)
	Storage.unreserve(store, item, 1)
	Storage.remove(store, item)
	needs.hunger = math.max(0, needs.hunger - ctx.config.food[item].fill)
end

-- One step, after the villager walked: ends the job when the facility is
-- gone; on arrival eats one item per config.eatTime until the plan is done
-- or hunger is 0.
function Eat.step(job, ctx)
	if job.dead then
		return
	end
	if job.source.building.dead or Walker.failed(job.villager.walker) then
		return Eat.finish(job)
	end
	if not Walker.idle(job.villager.walker) then
		return
	end
	job.stage = "eating"
	job.timer = job.timer + ctx.dt
	if job.timer < ctx.config.eatTime then
		return
	end
	job.timer = job.timer - ctx.config.eatTime
	eatOne(job, ctx)
	if #job.plan == 0 or job.villager.needs.hunger <= 0 then
		Eat.finish(job)
	end
end

return Eat
