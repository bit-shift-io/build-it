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

-- cache.baked lists every "<id>@v<version>@x<scale>" this cache baked.
function DesignCache.new(config)
	return { config = config, sets = {}, baked = {} }
end

local function key(design, n, scale)
	return design.id .. "@v" .. n .. "@x" .. scale
end

-- Bakes every facing of version `n` of `design` at `scale`:
-- { [facing] = sprite }.
local function bake(cache, design, n, scale)
	local version = assert(design.versions[n], "design " .. design.id .. " has no version " .. n)
	local model = Draft.toModel(version, cache.config.builder)
	local set = {}
	for _, facing in ipairs(Model.FACINGS) do
		set[facing] = Baker.bake(model, facing, cache.config, scale)
	end
	return set
end

-- The baked sprite of version `n` of `design` turned to `facing` (one of
-- Model.FACINGS) at whole bake `scale` (Baker.bake's sprite). Bakes the
-- version's 4 facings at that scale on first use.
function DesignCache.sprite(cache, design, n, facing, scale)
	local k = key(design, n, scale)
	local set = cache.sets[k]
	if not set then
		set = bake(cache, design, n, scale)
		cache.sets[k] = set
		table.insert(cache.baked, k)
	end
	return set[facing]
end

return DesignCache
