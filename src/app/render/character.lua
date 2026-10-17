-- Draws each character as its baked voxel figure (src/game/props/character.lua)
-- in its animator's facing and frame, the footprint centred on the record's
-- position. Frames come from the prop cache (src/app/bake/prop_cache.lua),
-- in the props cache directory, so they bake once and rebake when the
-- character generator's version changes. Villagers draw the same figure
-- in their own shirt (Registry.villager), a second bake key, and go into
-- the world's depth sort (CharacterRender.addVillagerDraws).
local Projection = require("src.game.projection")
local Registry = require("src.game.props.registry")
local PropCache = require("src.app.bake.prop_cache")
local Needs = require("src.game.components.needs")
local Sleep = require("src.game.jobs.sleep")

local CharacterRender = {}

-- A collapsed villager is drawn dimmed and bluish.
local COLLAPSED_TINT = { 0.5, 0.5, 0.65 }

-- A sleeping villager is drawn dimmed, a little less than a collapsed one
-- (no separate lying-down sprite exists).
local SLEEPING_TINT = { 0.65, 0.65, 0.8 }

-- One character cache per cache directory, for the life of the process.
local caches = {}

local function cacheFor(config)
	local dir = config.props.cacheDir
	caches[dir] = caches[dir] or PropCache.new({ character = Registry.CHARACTER, villager = Registry.villager(config) }, config)
	return caches[dir]
end

-- The baked sprite of the character facing `direction` (an index into
-- Character.DIRECTIONS) in `frame`, at whole bake `scale`.
function CharacterRender.sprite(config, direction, frame, scale)
	return PropCache.sprite(cacheFor(config), "character", direction, frame, scale)
end

-- The tile position whose 1x1 footprint centres on record `r`.
local function footprintAt(r, config)
	return r.x / config.tileSize - 0.5, r.y / config.tileSize - 0.5
end

-- Appends { sprite, tileX, tileY, tint } per villager to `draws` for the world's
-- depth sort, frames baked at whole bake `scale`.
function CharacterRender.addVillagerDraws(draws, ctx, scale)
	local cache = cacheFor(ctx.config)
	for _, v in ipairs(ctx.pools.villagers) do
		local tileX, tileY = footprintAt(v, ctx.config)
		table.insert(draws, {
			sprite = PropCache.sprite(cache, "villager", v.animator.facing, v.animator.frame, scale),
			tileX = tileX,
			tileY = tileY,
			tint = Needs.collapsed(v.needs) and COLLAPSED_TINT or (Sleep.rate(v) and SLEEPING_TINT) or nil,
		})
	end
end

-- The screen rect { left, top, width, height } (world px at zoom 1) of
-- villager or character `r`'s sprite as drawn: it rises above its ground
-- tile in the 3/4 projection, so a tile test would miss it.
local function spriteRect(config, r, sprite)
	local p = Projection.new(config)
	local tileX, tileY = footprintAt(r, config)
	local left, top, s = Projection.placeSprite(p, sprite.frame, tileX, tileY)
	return left, top, sprite.frame.width * s, sprite.frame.height * s
end

-- The record (villager or character) whose sprite covers world px point
-- (px, py), or nil. The nearest to the viewer (largest y) wins.
function CharacterRender.at(ctx, px, py)
	local config = ctx.config
	local found
	for _, pool in ipairs({ ctx.pools.characters, ctx.pools.villagers }) do
		for _, r in ipairs(pool) do
			local sprite = CharacterRender.sprite(config, r.animator.facing, r.animator.frame, 1)
			local left, top, w, h = spriteRect(config, r, sprite)
			if px >= left and px < left + w and py >= top and py < top + h and (not found or r.y > found.y) then
				found = r
			end
		end
	end
	return found
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
		local tileX, tileY = footprintAt(c, config)
		local left, top, s = Projection.placeSprite(p, sprite.frame, tileX, tileY)
		love.graphics.draw(sprite.image, sprite.quad, left, top, 0, s, s)
	end
	love.graphics.pop()
end

return CharacterRender
