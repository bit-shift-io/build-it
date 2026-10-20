-- Draws the flat tile world: terrain and grid (render/terrain.lua), then
-- building port tile markers on the ground (render/buildings.lua), then
-- every baked sprite on its tile -- resource nodes (render/nodes.lua),
-- buildings, villagers (render/character.lua) and deer (render/animals.lua)
-- -- sorted by depth. Everything goes through the one projection of the
-- active view (src/game/projection.lua), the same one the baker uses.
-- Reads ctx, never mutates it.
local Projection = require("src.game.projection")
local Terrain = require("src.app.render.terrain")
local NodesRender = require("src.app.render.nodes")
local BuildingsRender = require("src.app.render.buildings")
local CharacterRender = require("src.app.render.character")
local AnimalsRender = require("src.app.render.animals")

local WorldRender = {}

-- Draws each { sprite, tileX, tileY } back to front: by the view's depth at
-- its footprint's nearest corner (south-east), then west to east. A sprite with a quad draws
-- that region of its image (an atlas). A draw with `alpha` (0..1) is
-- translucent: a construction site. A draw with `tint` ({ r, g, b }) is
-- darkened by it.
local function drawSprites(draws, p)
	for _, d in ipairs(draws) do
		d.order = Projection.depth(p, d.tileX + d.sprite.width, d.tileY + d.sprite.depth, 0)
	end
	table.sort(draws, function(a, b)
		if a.order ~= b.order then
			return a.order < b.order
		end
		return a.tileX < b.tileX
	end)

	love.graphics.push("all")
	-- Baked pixels are opaque or fully clear, so the canvas is effectively
	-- premultiplied; this keeps filtered sprite edges from darkening.
	love.graphics.setBlendMode("alpha", "premultiplied")
	for _, d in ipairs(draws) do
		local left, top, s = Projection.placeSprite(p, d.sprite.frame, d.tileX, d.tileY)
		local a = d.alpha or 1 -- premultiplied: the tint carries the alpha
		local t = d.tint or { 1, 1, 1 } -- a collapsed villager is dimmed
		love.graphics.setColor(a * t[1], a * t[2], a * t[3], a)
		if d.sprite.quad then
			love.graphics.draw(d.sprite.image, d.sprite.quad, left, top, 0, s, s)
		else
			love.graphics.draw(d.sprite.image, left, top, 0, s, s)
		end
	end
	love.graphics.pop()
end

-- zoom is the camera zoom: sprites bake at the whole scale at or above it.
-- viewName is a config.views key (default "topdown").
function WorldRender.draw(ctx, zoom, viewName)
	viewName = viewName or "topdown"
	local p = Projection.new(ctx.config, 1, ctx.config.views[viewName])
	Terrain.draw(ctx, p)

	local scale = Projection.bakeScale(zoom or 1)
	local draws = {}
	NodesRender.addDraws(draws, ctx, scale, viewName)
	BuildingsRender.addDraws(draws, ctx, scale, viewName)
	CharacterRender.addVillagerDraws(draws, ctx, scale, viewName)
	AnimalsRender.addDraws(draws, ctx, scale, viewName)
	BuildingsRender.drawPorts(ctx, p)
	drawSprites(draws, p)
	BuildingsRender.drawStatus(ctx, p)
end

return WorldRender
