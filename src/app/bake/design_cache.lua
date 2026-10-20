-- Baked design sprites (docs/CONTEXT.md "Design version", "Facing"): the 4
-- facings of a design version at a bake scale, for the world to draw.
--
-- Kept in memory only, never written to disk: a version is immutable and
-- its file holds everything needed to bake it, so after a relaunch the
-- facings rebake from the stored design on first use. All 4 facings of a
-- version bake together, at one whole bake scale (Projection.bakeScale).
local Draft = require("src.game.builder.draft")
local Model = require("src.game.blocks.model")
local Baker = require("src.app.bake.baker")

local DesignCache = {}

local DEFAULT_VIEW = "topdown"

-- cache.baked lists every "<id>@v<version>@x<scale>" this cache baked, with
-- "@<view>" appended for views other than 3/4 top-down.
function DesignCache.new(config)
	return { config = config, sets = {}, baked = {} }
end

local function key(design, n, scale, viewName)
	local k = design.id .. "@v" .. n .. "@x" .. scale
	return viewName == DEFAULT_VIEW and k or k .. "@" .. viewName
end

-- Bakes every facing of version `n` of `design` at `scale`:
-- { [facing] = sprite }.
local function bake(cache, design, n, scale, view)
	local version = assert(design.versions[n], "design " .. design.id .. " has no version " .. n)
	local model = Draft.toModel(version, cache.config.builder)
	local set = {}
	for _, facing in ipairs(Model.FACINGS) do
		set[facing] = Baker.bake(model, facing, cache.config, scale, view)
	end
	return set
end

-- The baked sprite of version `n` of `design` turned to `facing` (one of
-- Model.FACINGS) at whole bake `scale` (Baker.bake's sprite). Bakes the
-- version's 4 facings at that scale and view on first use. `viewName` is a
-- config.views key (default "topdown"); sprites of different views coexist.
function DesignCache.sprite(cache, design, n, facing, scale, viewName)
	viewName = viewName or DEFAULT_VIEW
	local k = key(design, n, scale, viewName)
	local set = cache.sets[k]
	if not set then
		set = bake(cache, design, n, scale, cache.config.views[viewName])
		cache.sets[k] = set
		table.insert(cache.baked, k)
	end
	return set[facing]
end

return DesignCache
