-- Draw module for ctx.pools.buildings and ctx.pools.sites: each building
-- as its design version's baked sprite for its facing
-- (src/app/bake/design_cache.lua), handed to the world's depth sort, and a
-- marker on every port tile, drawn flat on the ground; each construction
-- site as the same sprite, translucent, with how much of its cost has
-- arrived and how far its build has got.
local Projection = require("src.game.projection")
local DesignCache = require("src.app.bake.design_cache")
local Storage = require("src.game.components.storage")
local FunctionBrick = require("src.game.components.function_brick")
local Site = require("src.game.buildings.site")
local StorageFacility = require("src.game.components.storage_facility")

local BuildingsRender = {}

-- One design cache per config table, for the life of the process.
local caches = setmetatable({}, { __mode = "k" })

-- The baked sprite of version `n` of `design` turned to `facing`, at whole
-- bake `scale`. Shared by placed buildings and the placement ghost.
function BuildingsRender.sprite(config, design, n, facing, scale)
	caches[config] = caches[config] or DesignCache.new(config)
	return DesignCache.sprite(caches[config], design, n, facing, scale)
end

local SITE_ALPHA = 0.45

-- Appends { sprite, tileX, tileY } per building, and per site with
-- `alpha`, to `draws`.
function BuildingsRender.addDraws(draws, ctx, scale)
	for _, b in ipairs(ctx.pools.buildings) do
		table.insert(draws, {
			sprite = BuildingsRender.sprite(ctx.config, b.design, b.version, b.facing, scale),
			tileX = b.tileX,
			tileY = b.tileY,
		})
	end
	for _, site in ipairs(ctx.pools.sites) do
		table.insert(draws, {
			sprite = BuildingsRender.sprite(ctx.config, site.design, site.version, site.facing, scale),
			tileX = site.tileX,
			tileY = site.tileY,
			alpha = SITE_ALPHA,
		})
	end
end

local PORT_COLORS = { input = { 0.3, 0.65, 1 }, output = { 1, 0.62, 0.2 } }
-- The way from a footprint edge out to its port tile.
local OUT = { N = { 0, -1 }, E = { 1, 0 }, S = { 0, 1 }, W = { -1, 0 } }

-- How full a port's buffer is: a bar along the tile's bottom edge, red
-- when full, and the item count. Ghost ports have no buffer.
local function drawFill(p, port, x, y)
	local buffer = port.buffer
	if not (buffer and buffer.capacity and buffer.capacity > 0) then
		return
	end
	local t = p.pixelsPerTile
	local n = Storage.total(buffer)
	local w, h = t * 0.8, math.max(2, t * 0.12)
	local bx, by = x + t * 0.1, y + t * 0.9 - h
	love.graphics.setColor(0, 0, 0, 0.6)
	love.graphics.rectangle("fill", bx, by, w, h)
	if n >= buffer.capacity then
		love.graphics.setColor(0.95, 0.2, 0.15, 1)
	else
		love.graphics.setColor(0.95, 0.95, 0.95, 1)
	end
	love.graphics.rectangle("fill", bx, by, w * n / buffer.capacity, h)
	if n > 0 then
		love.graphics.setColor(1, 1, 1, 1)
		love.graphics.print(tostring(n), x + t * 0.12, y + t * 0.08)
	end
end

-- A port tile marker: a coloured inset square, an arrow pointing into the
-- building for an input, out of it for an output, and its buffer's fill.
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
	drawFill(p, port, x, y)
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

local WORK_BAR = { 1, 0.85, 0.3 }
local DELIVERED_BAR = { 0.55, 0.8, 1 }
local SITE_LINE = { 1, 1, 1 }

-- A bar `w` wide at (x, y), filled to `fraction`, in `color`.
local function bar(x, y, w, h, fraction, color)
	love.graphics.setColor(0, 0, 0, 0.6)
	love.graphics.rectangle("fill", x, y, w, h)
	love.graphics.setColor(color[1], color[2], color[3], 1)
	love.graphics.rectangle("fill", x, y, w * math.max(0, math.min(1, fraction)), h)
end

-- Over a construction site: an outline round its footprint, the
-- delivered materials as a bar and "delivered/cost", and the build
-- progress as a second bar.
local function drawSite(ctx, p, site)
	local t = p.pixelsPerTile
	local x, y = Projection.worldToScreen(p, site.tileX, site.tileY, 0)
	local w, h = site.width * t, site.depth * t
	love.graphics.setColor(SITE_LINE[1], SITE_LINE[2], SITE_LINE[3], 0.7)
	love.graphics.rectangle("line", x, y, w, h)
	local need, have = 0, 0
	for item, n in pairs(site.cost) do
		need = need + n
		have = have + math.min(n, site.delivered.counts[item] or 0)
	end
	local bh = math.max(3, t * 0.12)
	local bx, bw = x + w * 0.1, w * 0.8
	local by = y + h / 2 - bh - 1
	bar(bx, by, bw, bh, need > 0 and have / need or 1, DELIVERED_BAR)
	bar(bx, by + bh + 2, bw, bh, site.progress / Site.buildTime(site, ctx.config), WORK_BAR)
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.print(have .. "/" .. need, bx, by - love.graphics.getFont():getHeight() - 2)
end

-- Over the sprites: for each function brick at work, a progress bar over
-- its node and a line to it from the building (a converter: over its
-- brick's tile, while its operator works there); for a full building, a red
-- outline round its footprint and "FULL"; for each site, drawSite.
function BuildingsRender.drawStatus(ctx, p)
	local t = p.pixelsPerTile
	love.graphics.push("all")
	love.graphics.setLineWidth(2)
	for _, b in ipairs(ctx.pools.buildings) do
		local bx, by = Projection.worldToScreen(p, b.tileX + b.width / 2, b.tileY + b.depth / 2, 0)
		for _, fb in ipairs(b.functionBricks) do
			local n = fb.node
			if n and fb.state == "working" and not b.full then
				local nx, ny = Projection.worldToScreen(p, n.tileX, n.tileY, 0)
				love.graphics.setColor(WORK_BAR[1], WORK_BAR[2], WORK_BAR[3], 0.5)
				love.graphics.line(bx, by, nx + t / 2, ny + t / 2)
				local cycle = FunctionBrick.cycle(b.traits, ctx.config)
				love.graphics.setColor(0, 0, 0, 0.6)
				love.graphics.rectangle("fill", nx + t * 0.1, ny + t * 0.4, t * 0.8, t * 0.12)
				love.graphics.setColor(WORK_BAR[1], WORK_BAR[2], WORK_BAR[3], 1)
				love.graphics.rectangle("fill", nx + t * 0.1, ny + t * 0.4, t * 0.8 * math.min(1, fb.progress / cycle), t * 0.12)
			elseif fb.recipe and fb.operator and fb.state == "working" then
				-- A converter at work: a progress bar over its brick's tile,
				-- only while its operator waits out the cycle there.
				local fx, fy = Projection.worldToScreen(p, fb.tileX, fb.tileY, 0)
				local cycle = FunctionBrick.cycle(b.traits, ctx.config, fb.recipe.cycle)
				love.graphics.setColor(0, 0, 0, 0.6)
				love.graphics.rectangle("fill", fx + t * 0.1, fy + t * 0.4, t * 0.8, t * 0.12)
				love.graphics.setColor(WORK_BAR[1], WORK_BAR[2], WORK_BAR[3], 1)
				love.graphics.rectangle("fill", fx + t * 0.1, fy + t * 0.4, t * 0.8 * math.min(1, fb.progress / cycle), t * 0.12)
			end
		end
		local fill = StorageFacility.is(b) and StorageFacility.fill(b)
		if fill then
			-- Fill bar and "NN%" over the footprint, red at 100%. Sits
			-- above the "FULL" tag when both show.
			local x, y = Projection.worldToScreen(p, b.tileX, b.tileY, 0)
			local font = love.graphics.getFont()
			local label = fill.percent .. "%"
			local color = fill.percent >= 100 and { 0.95, 0.2, 0.15 } or { 0.35, 0.75, 0.35 }
			local lh = font:getHeight() + 4
			local ly = y - lh - 2 - (b.full and lh + 2 or 0)
			bar(x, ly + lh - 4, b.width * t, 4, fill.percent / 100, color)
			love.graphics.setColor(color[1], color[2], color[3], 1)
			love.graphics.print(label, x + (b.width * t - font:getWidth(label)) / 2, ly)
		end
		if b.full then
			local x, y = Projection.worldToScreen(p, b.tileX, b.tileY, 0)
			local font = love.graphics.getFont()
			local label = "FULL"
			local lw, lh = font:getWidth(label) + 8, font:getHeight() + 4
			local lx, ly = x + (b.width * t - lw) / 2, y - lh - 2
			love.graphics.setColor(0.95, 0.2, 0.15, 1)
			love.graphics.rectangle("line", x, y, b.width * t, b.depth * t)
			love.graphics.rectangle("fill", lx, ly, lw, lh)
			love.graphics.setColor(1, 1, 1, 1)
			love.graphics.print(label, lx + 4, ly + 2)
		end
	end
	for _, site in ipairs(ctx.pools.sites) do
		drawSite(ctx, p, site)
	end
	love.graphics.pop()
end

return BuildingsRender
