-- Draws the world's ground: grass and water tiles, then the tile grid.
-- The terrain becomes one image, a pixel per tile, built once per world and
-- drawn stretched over the ground in a single call. Reads the world, never
-- mutates it.
local World = require("src.game.world")
local Projection = require("src.game.projection")

local Terrain = {}

local COLORS = {
	grass = { 0.22, 0.36, 0.2, 1 },
	water = { 0.2, 0.38, 0.62, 1 },
}
local GRID = { 0.17, 0.29, 0.16, 1 }

-- Terrain images by world table; weak, so a dropped world frees its image.
local images = setmetatable({}, { __mode = "k" })

local function terrainImage(world)
	if not world.terrain then
		return nil
	end
	if not images[world] then
		local data = love.image.newImageData(world.width, world.height)
		for y = 0, world.height - 1 do
			for x = 0, world.width - 1 do
				data:setPixel(x, y, unpack(COLORS[World.terrainAt(world, x, y)]))
			end
		end
		local image = love.graphics.newImage(data)
		image:setFilter("nearest", "nearest")
		images[world] = image
	end
	return images[world]
end

function Terrain.draw(ctx, p)
	local world = ctx.world
	-- The world's ground outline: a rectangle, or a diamond in an iso view.
	local x0, y0 = Projection.worldToScreen(p, 0, 0, 0)
	local x1, y1 = Projection.worldToScreen(p, world.width, 0, 0)
	local x2, y2 = Projection.worldToScreen(p, world.width, world.height, 0)
	local x3, y3 = Projection.worldToScreen(p, 0, world.height, 0)

	love.graphics.setColor(COLORS.grass)
	love.graphics.polygon("fill", x0, y0, x1, y1, x2, y2, x3, y3)

	local image = terrainImage(world)
	if image then
		-- One pixel per tile, through the ground matrix: the image's pixel
		-- (u, v) is tile (u, v), so nearest sampling keeps every tile edge
		-- on the tile grid (the GPU clips to the screen).
		local ppt = p.pixelsPerTile
		local ground = love.math.newTransform()
		ground:setMatrix("row", p.a * ppt, p.b * ppt, 0, 0, p.c * ppt, p.d * ppt, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
		love.graphics.push()
		love.graphics.applyTransform(ground)
		love.graphics.setColor(1, 1, 1, 1)
		love.graphics.draw(image, 0, 0)
		love.graphics.pop()
	end

	love.graphics.setColor(GRID)
	love.graphics.setLineWidth(1)
	for col = 0, world.width do
		local ax, ay = Projection.worldToScreen(p, col, 0, 0)
		local bx, by = Projection.worldToScreen(p, col, world.height, 0)
		love.graphics.line(ax, ay, bx, by)
	end
	for row = 0, world.height do
		local ax, ay = Projection.worldToScreen(p, 0, row, 0)
		local bx, by = Projection.worldToScreen(p, world.width, row, 0)
		love.graphics.line(ax, ay, bx, by)
	end
end

return Terrain
