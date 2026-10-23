-- Baked building sprites (docs/CONTEXT.md "Blueprint", "Facing", "Team
-- palette"; ADR 0007): the 4 facings of a blueprint's triangle mesh at a
-- bake scale, for the world to draw. Keyed by the blueprint's content hash,
-- so buildings with equal blueprints share sprites whatever design they
-- came from, and by the owner's team palette, which the mesh's team slots
-- resolve to at bake: a new team colour bakes afresh.
--
-- Kept in memory only, never written to disk: a blueprint never changes
-- and holds everything needed to bake it, so after a relaunch the facings
-- rebake on first use. All 4 facings of a blueprint bake together, at one
-- whole bake scale (Projection.bakeScale).
local Placement = require("src.game.buildings.placement")
local Palette = require("src.game.palette")
local Baker = require("src.app.bake.baker")

local DesignCache = {}

local DEFAULT_VIEW = "topdown"

-- cache.baked lists every key (DesignCache.key) this cache baked.
function DesignCache.new(config)
	return { config = config, sets = {}, baked = {} }
end

-- The key of `blueprint`'s sprites at `scale` in view `viewName` with team
-- `palette`: "<hash>@x<scale>", then "@<view>" for views other than 3/4
-- top-down, then "@<Palette.key>" when a palette is given.
function DesignCache.key(blueprint, scale, viewName, palette)
	local k = blueprint.hash .. "@x" .. scale
	if viewName ~= DEFAULT_VIEW then
		k = k .. "@" .. viewName
	end
	return palette and k .. "@" .. Palette.key(palette) or k
end

-- Bakes every facing of `blueprint` at `scale`: { [facing] = sprite }.
local function bake(cache, blueprint, scale, view, palette)
	local set = {}
	for _, facing in ipairs(Placement.FACINGS) do
		set[facing] = Baker.bakeMesh(blueprint.mesh, blueprint.width, blueprint.depth, facing, cache.config, scale, view, palette)
	end
	return set
end

-- The baked sprite of `blueprint` turned to `facing` (one of Placement.FACINGS)
-- at whole bake `scale` (Baker.bakeMesh's sprite). Bakes the blueprint's 4
-- facings at that scale, view and palette on first use. `viewName` is a
-- config.views key (default "topdown"); sprites of different views coexist.
-- `palette` is the owner's team palette (src/game/palette.lua); without one
-- team slots keep the default palette's colours.
function DesignCache.sprite(cache, blueprint, facing, scale, viewName, palette)
	viewName = viewName or DEFAULT_VIEW
	local k = DesignCache.key(blueprint, scale, viewName, palette)
	local set = cache.sets[k]
	if not set then
		set = bake(cache, blueprint, scale, cache.config.views[viewName], palette)
		cache.sets[k] = set
		table.insert(cache.baked, k)
	end
	return set[facing]
end

return DesignCache
