-- Draws the flat tile world: a ground fill, the tile grid, then baked
-- sprites on their tiles, sorted by depth. Everything goes through the one
-- 3/4 projection (src/game/projection.lua), the same one the baker uses.
-- Reads ctx, never mutates it.
local World = require("src.game.world")
local Projection = require("src.game.projection")
local TestHouse = require("src.game.blocks.test_house")
local Baker = require("src.app.bake.baker")

local WorldRender = {}

local GROUND = { 0.22, 0.36, 0.2, 1 }
local GRID = { 0.17, 0.29, 0.16, 1 }

-- The test house model and its baked sprites, keyed "<facing>:<scale>".
-- Baked lazily: only the facings and bake scales actually drawn.
local houseModel = nil
local houseSprites = {}

local function houseSprite(facing, scale, config)
	houseModel = houseModel or TestHouse.model()
	local key = facing .. ":" .. scale
	if not houseSprites[key] then
		houseSprites[key] = Baker.bake(houseModel, facing, config, scale)
	end
	return houseSprites[key]
end

local function drawGround(ctx, p)
	local w, h = World.pixelSize(ctx.world, ctx.config)

	love.graphics.setColor(GROUND)
	love.graphics.rectangle("fill", 0, 0, w, h)

	love.graphics.setColor(GRID)
	love.graphics.setLineWidth(1)
	for col = 0, ctx.world.width do
		local x0, y0 = Projection.worldToScreen(p, col, 0, 0)
		local x1, y1 = Projection.worldToScreen(p, col, ctx.world.height, 0)
		love.graphics.line(x0, y0, x1, y1)
	end
	for row = 0, ctx.world.height do
		local x0, y0 = Projection.worldToScreen(p, 0, row, 0)
		local x1, y1 = Projection.worldToScreen(p, ctx.world.width, row, 0)
		love.graphics.line(x0, y0, x1, y1)
	end
end

-- Draws each { sprite, tileX, tileY } back to front: by the depth of its
-- footprint's south edge, then west to east.
local function drawSprites(draws, p)
	for _, d in ipairs(draws) do
		d.order = Projection.depth(p, d.tileX, d.tileY + d.sprite.depth, 0)
	end
	table.sort(draws, function(a, b)
		if a.order ~= b.order then
			return a.order < b.order
		end
		return a.tileX < b.tileX
	end)

	love.graphics.push("all")
	love.graphics.setColor(1, 1, 1, 1)
	-- Baked pixels are opaque or fully clear, so the canvas is effectively
	-- premultiplied; this keeps filtered sprite edges from darkening.
	love.graphics.setBlendMode("alpha", "premultiplied")
	for _, d in ipairs(draws) do
		local left, top, s = Projection.placeSprite(p, d.sprite.frame, d.tileX, d.tileY)
		love.graphics.draw(d.sprite.image, left, top, 0, s, s)
	end
	love.graphics.pop()
end

-- zoom is the camera zoom: sprites bake at the whole scale at or above it.
function WorldRender.draw(ctx, zoom)
	local p = Projection.new(ctx.config)
	drawGround(ctx, p)

	local scale = Projection.bakeScale(zoom or 1)
	local draws = {}
	for _, place in ipairs(TestHouse.placements(ctx.world, ctx.config)) do
		table.insert(draws, {
			sprite = houseSprite(place.facing, scale, ctx.config),
			tileX = place.tileX,
			tileY = place.tileY,
		})
	end
	drawSprites(draws, p)
end

return WorldRender
