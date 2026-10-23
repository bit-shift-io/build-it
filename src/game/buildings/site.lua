-- A construction site (docs/CONTEXT.md "Construction site"): a placed
-- blueprint not yet built, in ctx.pools.sites. Its cost stays in the
-- storage facilities, claimed (Storage.claim), until haul jobs carry it
-- here; once all of it is delivered a build job (src/game/jobs/build.lua)
-- works for Site.buildTime, then BuildingSystem turns the site into a
-- building. Plain data, pure -- no `love.*`.
--
--   { design,               -- the design's name, a label only
--     blueprint,              -- frozen at placement (blueprint.lua)
--     facing, tileX, tileY, width, depth,
--     ports = {},             -- none: its port tiles stay open ground
--     cost = { [item] = n },  -- what it takes, all of it
--     delivered = <Storage>,  -- what haulers brought; capacity: the cost
--     claims = { <claim>, ... }, -- StorageFacility.claim's, still to haul
--     progress,               -- seconds built so far
--     builder = <build job> | nil, dead = true once built }
local Storage = require("src.game.components.storage")

local Site = {}

-- A new site for `request` (Placement's) and its `blueprint`, footprint
-- width x depth, taking `cost` already claimed as `claims`.
function Site.new(request, blueprint, width, depth, cost, claims)
	local total = 0
	for _, n in pairs(cost) do
		total = total + n
	end
	return {
		design = request.design,
		blueprint = blueprint,
		facing = request.facing,
		tileX = request.tileX,
		tileY = request.tileY,
		width = width,
		depth = depth,
		ports = {},
		cost = cost,
		delivered = Storage.new(total),
		claims = claims,
		progress = 0,
	}
end

-- The placement request the site stands for, with its blueprint.
function Site.request(site)
	return {
		design = site.design,
		blueprint = site.blueprint,
		facing = site.facing,
		tileX = site.tileX,
		tileY = site.tileY,
	}
end

-- Whether every item of the cost has been delivered.
function Site.supplied(site)
	for item, n in pairs(site.cost) do
		if (site.delivered.counts[item] or 0) < n then
			return false
		end
	end
	return true
end

-- Seconds a build job works on the site: config.villagers.buildTime per
-- footprint tile.
function Site.buildTime(site, config)
	return config.villagers.buildTime * site.width * site.depth
end

-- Whether the build job is done and the site may become a building.
function Site.built(site, config)
	return site.progress >= Site.buildTime(site, config)
end

return Site
