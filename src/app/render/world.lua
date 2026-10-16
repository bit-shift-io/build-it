-- Draws the flat tile world: terrain and grid (render/terrain.lua), then
-- building port tile markers on the ground (render/buildings.lua), then
-- every baked sprite on its tile -- resource nodes (render/nodes.lua),
-- buildings and the test house row -- sorted by depth. Everything goes through the one
-- 3/4 projection (src/game/projection.lua), the same one the baker uses.
-- Reads ctx, never mutates it.
local Projection = require("src.game.projection")
local TestHouse = require("src.game.blocks.test_house")
local Baker = require("src.app.bake.baker")
local Terrain = require("src.app.render.terrain")
local NodesRender = require("src.app.render.nodes")
local BuildingsRender = require("src.app.render.buildings")

local WorldRender = {}

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

-- Draws each { sprite, tileX, tileY } back to front: by the depth of its
-- footprint's south edge, then west to east. A sprite with a quad draws
-- that region of its image (an atlas).
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
		if d.sprite.quad then
			love.graphics.draw(d.sprite.image, d.sprite.quad, left, top, 0, s, s)
		else
			love.graphics.draw(d.sprite.image, left, top, 0, s, s)
		end
	end
	love.graphics.pop()
end

-- zoom is the camera zoom: sprites bake at the whole scale at or above it.
function WorldRender.draw(ctx, zoom)
	local p = Projection.new(ctx.config)
	Terrain.draw(ctx, p)

	local scale = Projection.bakeScale(zoom or 1)
	local draws = {}
	for _, place in ipairs(TestHouse.placements(ctx.world, ctx.config)) do
		table.insert(draws, {
			sprite = houseSprite(place.facing, scale, ctx.config),
			tileX = place.tileX,
			tileY = place.tileY,
		})
	end
	NodesRender.addDraws(draws, ctx, scale)
	BuildingsRender.addDraws(draws, ctx, scale)
	BuildingsRender.drawPorts(ctx, p)
	drawSprites(draws, p)
	BuildingsRender.drawStatus(ctx, p)
end

return WorldRender
