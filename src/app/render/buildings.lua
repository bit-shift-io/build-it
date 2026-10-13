-- Draw module for ctx.pools.buildings: each building as its design
-- version's baked sprite for its facing (src/app/bake/design_cache.lua),
-- handed to the world's depth sort, and a marker on every port tile, drawn
-- flat on the ground.
local Projection = require("src.game.projection")
local DesignCache = require("src.app.bake.design_cache")

local BuildingsRender = {}

-- One design cache per config table, for the life of the process.
local caches = setmetatable({}, { __mode = "k" })

-- The baked sprite of version `n` of `design` turned to `facing`, at whole
-- bake `scale`. Shared by placed buildings and the placement ghost.
function BuildingsRender.sprite(config, design, n, facing, scale)
	caches[config] = caches[config] or DesignCache.new(config)
	return DesignCache.sprite(caches[config], design, n, facing, scale)
end

-- Appends { sprite, tileX, tileY } per building to `draws`.
function BuildingsRender.addDraws(draws, ctx, scale)
	for _, b in ipairs(ctx.pools.buildings) do
		table.insert(draws, {
			sprite = BuildingsRender.sprite(ctx.config, b.design, b.version, b.facing, scale),
			tileX = b.tileX,
			tileY = b.tileY,
		})
	end
end

local PORT_COLORS = { input = { 0.3, 0.65, 1 }, output = { 1, 0.62, 0.2 } }
-- The way from a footprint edge out to its port tile.
local OUT = { N = { 0, -1 }, E = { 1, 0 }, S = { 0, 1 }, W = { -1, 0 } }

-- A port tile marker: a coloured inset square, and an arrow pointing into
-- the building for an input, out of it for an output.
function BuildingsRender.drawPort(p, port)
	local t = p.pixelsPerTile
	local x, y = Projection.worldToScreen(p, port.x, port.y, 0)
	local color = PORT_COLORS[port.kind] or { 1, 1, 1 }
	love.graphics.setColor(color[1], color[2], color[3], 0.35)
	love.graphics.rectangle("fill", x + t * 0.1, y + t * 0.1, t * 0.8, t * 0.8)
	love.graphics.setColor(color[1], color[2], color[3], 1)
	love.graphics.setLineWidth(2)
	love.graphics.rectangle("line", x + t * 0.1, y + t * 0.1, t * 0.8, t * 0.8)

	local out = OUT[port.side]
	local dx, dy = out[1], out[2]
	if port.kind == "input" then
		dx, dy = -dx, -dy
	end
	local cx, cy, r = x + t / 2, y + t / 2, t * 0.25
	love.graphics.polygon(
		"fill",
		cx + dx * r,
		cy + dy * r,
		cx - dx * r - dy * r,
		cy - dy * r + dx * r,
		cx - dx * r + dy * r,
		cy - dy * r - dx * r
	)
end

-- Every placed building's port tile markers.
function BuildingsRender.drawPorts(ctx, p)
	love.graphics.push("all")
	for _, b in ipairs(ctx.pools.buildings) do
		for _, port in ipairs(b.ports) do
			BuildingsRender.drawPort(p, port)
		end
	end
	love.graphics.pop()
end

return BuildingsRender
