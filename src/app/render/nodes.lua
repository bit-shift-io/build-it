-- Draw module for ctx.pools.nodes: each tree and rock as its variant's baked
-- sprite at its stage, from the prop cache (src/app/bake/prop_cache.lua).
-- Hands its sprites to the world's depth sort rather than drawing them.
local Registry = require("src.game.props.registry")
local PropCache = require("src.app.bake.prop_cache")

local NodesRender = {}

-- One prop cache per cache directory, for the life of the process.
local caches = {}

local function cacheFor(config)
	local dir = config.props.cacheDir
	caches[dir] = caches[dir] or PropCache.new(Registry.KINDS, config)
	return caches[dir]
end

-- Appends { sprite, tileX, tileY } per node to `draws`, sprites baked at
-- whole bake `scale`, in view `viewName`.
function NodesRender.addDraws(draws, ctx, scale, viewName)
	local cache = cacheFor(ctx.config)
	for _, n in ipairs(ctx.pools.nodes) do
		table.insert(draws, {
			sprite = PropCache.sprite(cache, n.kind, n.variant, n.stage, scale, viewName),
			tileX = n.tileX,
			tileY = n.tileY,
		})
	end
end

return NodesRender
