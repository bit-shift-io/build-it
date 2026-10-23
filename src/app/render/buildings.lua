-- Draw module for ctx.pools.buildings and ctx.pools.sites: each building
-- as its blueprint's baked sprite for its facing
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

-- The baked sprite of `blueprint` turned to `facing`, at whole bake
-- `scale`, in view `viewName` (a config.views key, default "topdown").
-- Shared by placed buildings, the placement ghost and the picker.
function BuildingsRender.sprite(config, blueprint, facing, scale, viewName)
	caches[config] = caches[config] or DesignCache.new(config)
	return DesignCache.sprite(caches[config], blueprint, facing, scale, viewName)
end

local SITE_ALPHA = 0.45

-- Appends { sprite, tileX, tileY } per building, and per site with
-- `alpha`, to `draws`.
function BuildingsRender.addDraws(draws, ctx, scale, viewName)
	for _, b in ipairs(ctx.pools.buildings) do
		table.insert(draws, {
			sprite = BuildingsRender.sprite(ctx.config, b.blueprint, b.facing, scale, viewName),
			tileX = b.tileX,
			tileY = b.tileY,
		})
	end
	for _, site in ipairs(ctx.pools.sites) do
		table.insert(draws, {
			sprite = BuildingsRender.sprite(ctx.config, site.blueprint, site.facing, scale, viewName),
			tileX = site.tileX,
			tileY = site.tileY,
			alpha = SITE_ALPHA,
		})
	end
end

local PORT_COLORS = { input = { 0.3, 0.65, 1 }, output = { 1, 0.62, 0.2 } }
-- The way from a footprint edge out to its port tile.
local OUT = { N = { 0, -1 }, E = { 1, 0 }, S = { 0, 1 }, W = { -1, 0 } }

-- The flat point list of the ground rectangle (u0, v0)-(u1, v1), in tiles
-- from tile (x, y), as the view draws it: a rectangle, or a diamond in an
-- iso view.
local function groundRect(p, x, y, u0, v0, u1, v1)
	local ax, ay = Projection.worldToScreen(p, x + u0, y + v0, 0)
	local bx, by = Projection.worldToScreen(p, x + u1, y + v0, 0)
	local cx, cy = Projection.worldToScreen(p, x + u1, y + v1, 0)
	local dx, dy = Projection.worldToScreen(p, x + u0, y + v1, 0)
	return { ax, ay, bx, by, cx, cy, dx, dy }
end
BuildingsRender.groundRect = groundRect

-- Where a tile footprint's label sits: its screen centre x and the top of
-- its screen extent.
local function footprintTop(p, x, y, w, d)
	local pts = groundRect(p, x, y, 0, 0, w, d)
	local top = math.huge
	for i = 2, #pts, 2 do
		top = math.min(top, pts[i])
	end
	local cx = Projection.worldToScreen(p, x + w / 2, y + d / 2, 0)
	return cx, top
end

-- How full a port's buffer is: a bar along the tile's bottom edge, red
-- when full, and the item count. Ghost ports have no buffer.
local function drawFill(p, port)
	local buffer = port.buffer
	if not (buffer and buffer.capacity and buffer.capacity > 0) then
		return
	end
	local t = p.pixelsPerTile
	local n = Storage.total(buffer)
	local h = math.max(2, t * 0.12) / t
	love.graphics.setColor(0, 0, 0, 0.6)
	love.graphics.polygon("fill", groundRect(p, port.x, port.y, 0.1, 0.9 - h, 0.9, 0.9))
	if n >= buffer.capacity then
		love.graphics.setColor(0.95, 0.2, 0.15, 1)
	else
		love.graphics.setColor(0.95, 0.95, 0.95, 1)
	end
	love.graphics.polygon("fill", groundRect(p, port.x, port.y, 0.1, 0.9 - h, 0.1 + 0.8 * n / buffer.capacity, 0.9))
	if n > 0 then
		love.graphics.setColor(1, 1, 1, 1)
		local cx, cy = Projection.worldToScreen(p, port.x + 0.5, port.y + 0.5, 0)
		love.graphics.print(tostring(n), cx - t * 0.38, cy - t * 0.42)
	end
end

-- A port tile marker: a coloured inset square, an arrow pointing into the
-- building for an input, out of it for an output, and its buffer's fill.
function BuildingsRender.drawPort(p, port)
	local color = PORT_COLORS[port.kind] or { 1, 1, 1 }
	love.graphics.setColor(color[1], color[2], color[3], 0.35)
	love.graphics.polygon("fill", groundRect(p, port.x, port.y, 0.1, 0.1, 0.9, 0.9))
	love.graphics.setColor(color[1], color[2], color[3], 1)
	love.graphics.setLineWidth(2)
	love.graphics.polygon("line", groundRect(p, port.x, port.y, 0.1, 0.1, 0.9, 0.9))

	local out = OUT[port.side]
	local dx, dy = out[1], out[2]
	if port.kind == "input" then
		dx, dy = -dx, -dy
	end
	local r = 0.25
	local function at(u, v)
		return Projection.worldToScreen(p, port.x + u, port.y + v, 0)
	end
	local ax, ay = at(0.5 + dx * r, 0.5 + dy * r)
	local bx, by = at(0.5 - dx * r - dy * r, 0.5 - dy * r + dx * r)
	local cx, cy = at(0.5 - dx * r + dy * r, 0.5 - dy * r - dx * r)
	love.graphics.polygon("fill", ax, ay, bx, by, cx, cy)
	drawFill(p, port)
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
-- progress as a second bar, centred on the footprint.
local function drawSite(ctx, p, site)
	local t = p.pixelsPerTile
	local w = site.width * t
	love.graphics.setColor(SITE_LINE[1], SITE_LINE[2], SITE_LINE[3], 0.7)
	love.graphics.polygon("line", groundRect(p, site.tileX, site.tileY, 0, 0, site.width, site.depth))
	local need, have = 0, 0
	for item, n in pairs(site.cost) do
		need = need + n
		have = have + math.min(n, site.delivered.counts[item] or 0)
	end
	local cx, cy = Projection.worldToScreen(p, site.tileX + site.width / 2, site.tileY + site.depth / 2, 0)
	local bh = math.max(3, t * 0.12)
	local bx, bw = cx - w * 0.4, w * 0.8
	local by = cy - bh - 1
	bar(bx, by, bw, bh, need > 0 and have / need or 1, DELIVERED_BAR)
	bar(bx, by + bh + 2, bw, bh, site.progress / Site.buildTime(site, ctx.config), WORK_BAR)
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.print(have .. "/" .. need, bx, by - love.graphics.getFont():getHeight() - 2)
end

-- A work progress bar over the tile (tileX, tileY): 0.8 tile wide, centred
-- on the tile, a little above its middle.
local function drawTileProgress(p, tileX, tileY, fraction)
	local t = p.pixelsPerTile
	local cx, cy = Projection.worldToScreen(p, tileX + 0.5, tileY + 0.5, 0)
	love.graphics.setColor(0, 0, 0, 0.6)
	love.graphics.rectangle("fill", cx - t * 0.4, cy - t * 0.1, t * 0.8, t * 0.12)
	love.graphics.setColor(WORK_BAR[1], WORK_BAR[2], WORK_BAR[3], 1)
	love.graphics.rectangle("fill", cx - t * 0.4, cy - t * 0.1, t * 0.8 * math.min(1, fraction), t * 0.12)
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
				local nx, ny = Projection.worldToScreen(p, n.tileX + 0.5, n.tileY + 0.5, 0)
				love.graphics.setColor(WORK_BAR[1], WORK_BAR[2], WORK_BAR[3], 0.5)
				love.graphics.line(bx, by, nx, ny)
				local cycle = FunctionBrick.cycle(b.traits, ctx.config)
				drawTileProgress(p, n.tileX, n.tileY, fb.progress / cycle)
			elseif fb.recipe and fb.operator and fb.state == "working" then
				-- A converter at work: a progress bar over its brick's tile,
				-- only while its operator waits out the cycle there.
				local cycle = FunctionBrick.cycle(b.traits, ctx.config, fb.recipe.cycle)
				drawTileProgress(p, fb.tileX, fb.tileY, fb.progress / cycle)
			end
		end
		local fill = StorageFacility.is(b) and StorageFacility.fill(b)
		if fill then
			-- Fill bar and "NN%" over the footprint, red at 100%. Sits
			-- above the "FULL" tag when both show.
			local cx, top = footprintTop(p, b.tileX, b.tileY, b.width, b.depth)
			local font = love.graphics.getFont()
			local label = fill.percent .. "%"
			local color = fill.percent >= 100 and { 0.95, 0.2, 0.15 } or { 0.35, 0.75, 0.35 }
			local lh = font:getHeight() + 4
			local ly = top - lh - 2 - (b.full and lh + 2 or 0)
			bar(cx - b.width * t / 2, ly + lh - 4, b.width * t, 4, fill.percent / 100, color)
			love.graphics.setColor(color[1], color[2], color[3], 1)
			love.graphics.print(label, cx - font:getWidth(label) / 2, ly)
		end
		if b.full then
			local cx, top = footprintTop(p, b.tileX, b.tileY, b.width, b.depth)
			local font = love.graphics.getFont()
			local label = "FULL"
			local lw, lh = font:getWidth(label) + 8, font:getHeight() + 4
			local lx, ly = cx - lw / 2, top - lh - 2
			love.graphics.setColor(0.95, 0.2, 0.15, 1)
			love.graphics.polygon("line", groundRect(p, b.tileX, b.tileY, 0, 0, b.width, b.depth))
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
