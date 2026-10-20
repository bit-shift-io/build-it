-- Draw module for ctx.pools.animals: each deer as its baked sprite
-- (src/game/props/deer.lua) in its animator's facing and frame, the 1x1
-- footprint centred on the record's position. Hands its sprites to the
-- world's depth sort rather than drawing them.
local Registry = require("src.game.props.registry")
local PropCache = require("src.app.bake.prop_cache")

local AnimalsRender = {}

-- One prop cache per cache directory, for the life of the process.
local caches = {}

local function cacheFor(config)
	local dir = config.props.cacheDir
	caches[dir] = caches[dir] or PropCache.new({ deer = Registry.DEER }, config)
	return caches[dir]
end

-- Appends { sprite, tileX, tileY } per deer to `draws`, sprites baked at
-- whole bake `scale`, in view `viewName`.
function AnimalsRender.addDraws(draws, ctx, scale, viewName)
	local cache = cacheFor(ctx.config)
	local tile = ctx.config.tileSize
	for _, a in ipairs(ctx.pools.animals) do
		table.insert(draws, {
			sprite = PropCache.sprite(cache, "deer", a.animator.facing, a.animator.frame, scale, viewName),
			tileX = a.x / tile - 0.5,
			tileY = a.y / tile - 0.5,
		})
	end
end

return AnimalsRender
