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
--
-- A blueprint also has a cutaway sprite set (docs/CONTEXT.md "Cutaway"):
-- its mesh clipped at half config.walk.bodyHeight, cached the same way
-- under its own key. Cut wall tops are left open; walls are thin.
local Placement = require("src.game.buildings.placement")
local Palette = require("src.game.palette")
local Baker = require("src.app.bake.baker")
local Clip = require("src.game.geometry.clip")

local DesignCache = {}

local DEFAULT_VIEW = "topdown"

-- cache.baked lists every key (DesignCache.key) this cache baked.
function DesignCache.new(config)
	return { config = config, sets = {}, baked = {} }
end

-- The key of `blueprint`'s sprites at `scale` in view `viewName` with team
-- `palette`: "<hash>@x<scale>", then "@<view>" for views other than 3/4
-- top-down, then "@cutaway" for the cutaway set when `cutaway` is true,
-- then "@<Palette.key>" when a palette is given. A palette's
-- key is worked out once per palette table (palettes are never changed in
-- place; a new colour is a new palette).
local paletteKeys = setmetatable({}, { __mode = "k" })
function DesignCache.key(blueprint, scale, viewName, palette, cutaway)
	local k = blueprint.hash .. "@x" .. scale
	if viewName ~= DEFAULT_VIEW then
		k = k .. "@" .. viewName
	end
	if cutaway then
		k = k .. "@cutaway"
	end
	if not palette then
		return k
	end
	paletteKeys[palette] = paletteKeys[palette] or Palette.key(palette)
	return k .. "@" .. paletteKeys[palette]
end

-- Bakes every facing of `triangles` (`blueprint`'s mesh, whole or cut) at
-- `scale`: { [facing] = sprite }.
local function bake(cache, blueprint, triangles, scale, view, palette)
	local set = {}
	for _, facing in ipairs(Placement.FACINGS) do
		set[facing] = Baker.bakeMesh(triangles, blueprint.width, blueprint.depth, facing, cache.config, scale, view, palette)
	end
	return set
end

-- The sprite set under key `k`, baked from `triangles` on first use.
local function cached(cache, k, blueprint, triangles, scale, viewName, palette)
	local set = cache.sets[k]
	if not set then
		set = bake(cache, blueprint, triangles, scale, cache.config.views[viewName], palette)
		cache.sets[k] = set
		table.insert(cache.baked, k)
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
	return cached(cache, k, blueprint, blueprint.mesh, scale, viewName, palette)[facing]
end

-- Like DesignCache.sprite, but `blueprint` cut away: its mesh clipped at
-- half config.walk.bodyHeight. A mesh with nothing that low has no cutaway;
-- its full sprite stands in.
function DesignCache.cutaway(cache, blueprint, facing, scale, viewName, palette)
	viewName = viewName or DEFAULT_VIEW
	local k = DesignCache.key(blueprint, scale, viewName, palette, true)
	local set = cache.sets[k]
	if not set then
		local cut = Clip.below(blueprint.mesh, cache.config.walk.bodyHeight / 2)
		if #cut == 0 then
			return DesignCache.sprite(cache, blueprint, facing, scale, viewName, palette)
		end
		set = cached(cache, k, blueprint, cut, scale, viewName, palette)
	end
	return set[facing]
end

return DesignCache
