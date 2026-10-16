-- Draws each character as its baked voxel figure (src/game/props/character.lua)
-- in its animator's facing and frame, the footprint centred on the record's
-- position. Frames come from the prop cache (src/app/bake/prop_cache.lua),
-- in the props cache directory, so they bake once and rebake when the
-- character generator's version changes.
local Projection = require("src.game.projection")
local Registry = require("src.game.props.registry")
local PropCache = require("src.app.bake.prop_cache")

local CharacterRender = {}

-- One character cache per cache directory, for the life of the process.
local caches = {}

local function cacheFor(config)
	local dir = config.props.cacheDir
	caches[dir] = caches[dir] or PropCache.new({ character = Registry.CHARACTER }, config)
	return caches[dir]
end

-- The baked sprite of the character facing `direction` (an index into
-- Character.DIRECTIONS) in `frame`, at whole bake `scale`.
function CharacterRender.sprite(config, direction, frame, scale)
	return PropCache.sprite(cacheFor(config), "character", direction, frame, scale)
end

-- zoom is the camera zoom: frames bake at the whole scale at or above it.
function CharacterRender.draw(ctx, zoom)
	local config = ctx.config
	local p = Projection.new(config)
	local scale = Projection.bakeScale(zoom or 1)
	love.graphics.push("all")
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.setBlendMode("alpha", "premultiplied")
	for _, c in ipairs(ctx.pools.characters) do
		local sprite = CharacterRender.sprite(config, c.animator.facing, c.animator.frame, scale)
		-- The 1x1 footprint's centre on the record's position.
		local tileX, tileY = c.x / config.tileSize - 0.5, c.y / config.tileSize - 0.5
		local left, top, s = Projection.placeSprite(p, sprite.frame, tileX, tileY)
		love.graphics.draw(sprite.image, sprite.quad, left, top, 0, s, s)
	end
	love.graphics.pop()
end

return CharacterRender
