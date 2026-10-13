-- Draws the flat tile world: a ground fill and the tile grid. Reads ctx,
-- never mutates it.
local World = require("src.game.world")

local WorldRender = {}

local GROUND = { 0.22, 0.36, 0.2, 1 }
local GRID = { 0.17, 0.29, 0.16, 1 }

function WorldRender.draw(ctx)
	local tile = ctx.config.tileSize
	local w, h = World.pixelSize(ctx.world, ctx.config)

	love.graphics.setColor(GROUND)
	love.graphics.rectangle("fill", 0, 0, w, h)

	love.graphics.setColor(GRID)
	love.graphics.setLineWidth(1)
	for col = 0, ctx.world.width do
		love.graphics.line(col * tile, 0, col * tile, h)
	end
	for row = 0, ctx.world.height do
		love.graphics.line(0, row * tile, w, row * tile)
	end
end

return WorldRender
