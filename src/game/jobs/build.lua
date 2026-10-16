-- A build job (docs/CONTEXT.md "Build job"): one villager turns one
-- construction site (src/game/buildings/site.lua) whose materials are all
-- delivered into a building. It walks onto the site's footprint and works
-- there until the site's progress reaches Site.buildTime, then the job
-- ends; BuildingSystem turns the built site into a building. Plain data in
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

-- The footprint tile of `site` nearest pixel (px, py).
local function nearestTile(site, px, py, tile)
	local x, y = math.floor(px / tile), math.floor(py / tile)
	return math.max(site.tileX, math.min(x, site.tileX + site.width - 1)), math.max(site.tileY, math.min(y, site.tileY + site.depth - 1))
end

-- Gives `job` to villager `v` and sends it to the site's footprint tile
-- nearest it. False (and the job ended) when there is no route.
function Build.start(job, v, ctx)
	job.villager = v
	v.job = job
	local x, y = nearestTile(job.site, v.x, v.y, ctx.config.tileSize)
	if not Walker.goTo(v, ctx, x, y) then
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
	if not Walker.idle(job.villager.walker) then
		return
	end
	job.stage = "building"
	site.progress = math.min(site.progress + ctx.dt, Site.buildTime(site, ctx.config))
	if Site.built(site, ctx.config) then
		Build.finish(job)
	end
end

return Build
