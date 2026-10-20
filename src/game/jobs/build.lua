-- A build job (docs/CONTEXT.md "Build job"): one villager turns one
-- construction site (src/game/buildings/site.lua) whose materials are all
-- delivered into a building. It walks to a tile beside the site's footprint
-- and works there until the site's progress reaches Site.buildTime, then the
-- job ends; BuildingSystem turns the built site into a building. Plain data in
-- ctx.pools.jobs; src/game/systems/job_system.lua creates, assigns and
-- steps it. Pure -- no `love.*`.
--
--   job = { kind = "build", site, villager = <villager> | nil,
--           stage = "toSite"|"building", dead = true when ended }
--
-- The site's `builder` is the job while it is held. Progress lives on the
-- site, so a new builder (after a load) carries on where the last stopped.
local Walker = require("src.game.components.walker")
local Site = require("src.game.buildings.site")
local World = require("src.game.world")
local Aura = require("src.game.components.aura")

local Build = {}

function Build.new(site)
	local job = { kind = "build", site = site, stage = "toSite" }
	site.builder = job
	return job
end

-- Ends `job`: the site and the villager are free again.
function Build.finish(job)
	if job.dead then
		return
	end
	job.dead = true
	job.site.builder = nil
	if job.villager then
		job.villager.job = nil
	end
end

-- Gives `job` to villager `v` and sends it to the tile beside the site's
-- footprint nearest it. False (and the job ended) when there is no route.
function Build.start(job, v, ctx)
	job.villager = v
	v.job = job
	local tile = ctx.config.tileSize
	local x, y = World.tileBeside(ctx.world, job.site, math.floor(v.x / tile), math.floor(v.y / tile))
	if not x or not Walker.goTo(v, ctx, x, y) then
		Build.finish(job)
		return false
	end
	return true
end

-- One step, after the villager walked: once it stands on the site it
-- builds for ctx.dt; the job ends when the site is built.
function Build.step(job, ctx)
	if job.dead then
		return
	end
	local site = job.site
	if site.dead then
		return Build.finish(job)
	end
	if Walker.failed(job.villager.walker) then
		return Build.finish(job)
	end
	if not Walker.idle(job.villager.walker) then
		return
	end
	job.stage = "building"
	site.progress = math.min(site.progress + Aura.work(job.villager, ctx.dt), Site.buildTime(site, ctx.config))
	if Site.built(site, ctx.config) then
		Build.finish(job)
		local xp = job.villager.xp
		xp.build = (xp.build or 0) + 1
		-- Lingers beside the new building (docs/CONTEXT.md "Linger spot"); the
		-- site dies as it becomes one, so the anchor is a copy of its footprint.
		job.villager.linger = {
			task = { kind = "build" },
			anchor = { tileX = site.tileX, tileY = site.tileY, width = site.width, depth = site.depth },
		}
	end
end

return Build
