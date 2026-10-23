-- The placement ghost (src/app/screens/world.lua): the design being placed,
-- translucent over its footprint at the pointer, tinted green when the
-- placement is valid and red when not, with its port tile markers; and the
-- placement panel, in screen space.
local Projection = require("src.game.projection")
local Placement = require("src.game.buildings.placement")
local StorageFacility = require("src.game.components.storage_facility")
local BuildingsRender = require("src.app.render.buildings")

local GhostRender = {}

local VALID = { 0.35, 0.9, 0.45 }
local INVALID = { 0.95, 0.25, 0.2 }
local SPRITE_ALPHA = 0.75

-- ghost: WorldScreen.ghost's { request, ok, reason }. Draws in world space,
-- inside the camera, team slots in `palette`.
function GhostRender.draw(ctx, ghost, zoom, viewName, palette)
	viewName = viewName or "topdown"
	local p = Projection.new(ctx.config, 1, ctx.config.views[viewName])
	local req = ghost.request
	local blueprint = Placement.blueprint(req)
	local width, depth = Placement.footprint(blueprint, req.facing)
	local color = ghost.ok and VALID or INVALID
	local outline = BuildingsRender.groundRect(p, req.tileX, req.tileY, 0, 0, width, depth)

	love.graphics.push("all")
	love.graphics.setColor(color[1], color[2], color[3], 0.35)
	love.graphics.polygon("fill", outline)
	for _, port in ipairs(Placement.ports(blueprint, req.facing, req.tileX, req.tileY)) do
		BuildingsRender.drawPort(p, port)
	end

	local sprite = BuildingsRender.sprite(ctx.config, blueprint, req.facing, Projection.bakeScale(zoom or 1), viewName, palette)
	local left, top, s = Projection.placeSprite(p, sprite.frame, req.tileX, req.tileY)
	-- Premultiplied, like every baked sprite: the tint carries the alpha.
	local a = SPRITE_ALPHA
	local tint = ghost.ok and { 0.85, 1, 0.85 } or { 1, 0.55, 0.5 }
	love.graphics.setBlendMode("alpha", "premultiplied")
	love.graphics.setColor(tint[1] * a, tint[2] * a, tint[3] * a, a)
	love.graphics.draw(sprite.image, left, top, 0, s, s)

	love.graphics.setBlendMode("alpha")
	love.graphics.setColor(color[1], color[2], color[3], 1)
	love.graphics.setLineWidth(2)
	love.graphics.polygon("line", outline)
	love.graphics.pop()
end

local MARGIN, LINE = 8, 18
local WHITE, RED = { 1, 1, 1, 1 }, { 1, 0.45, 0.4, 1 }

-- The placement panel, bottom-left in screen space: while placing, what is
-- placed and how, and `status` (why the ghost or the last click is
-- refused), in red.
--   placing: { design = <name>, blueprint, facing } or nil;
--   cost: { [item] = n } or nil
function GhostRender.drawPanel(placing, cost, status, totals)
	local lines = {}
	if placing then
		local short = StorageFacility.short(cost or {}, totals or {})
		local items = {}
		for item in pairs(cost or {}) do
			table.insert(items, item)
		end
		table.sort(items)
		-- Coloured text: { colour, text, colour, text, ... }
		local text = { WHITE, string.format("Placing %s, facing %s. Cost: ", placing.design, placing.facing) }
		for i, item in ipairs(items) do
			table.insert(text, short[item] and RED or WHITE)
			table.insert(text, cost[item] .. " " .. item .. (i < #items and ", " or ""))
		end
		table.insert(lines, text)
		table.insert(lines, "R turn, click place, Esc or right-click cancel")
	end
	if #lines == 0 and not status then
		return
	end

	local _, h = love.graphics.getDimensions()
	local count = #lines + (status and 1 or 0)
	local top = h - MARGIN - count * LINE
	love.graphics.push("all")
	love.graphics.setColor(0, 0, 0, 0.5)
	love.graphics.rectangle("fill", MARGIN - 4, top - 4, 520, count * LINE + 8)
	love.graphics.setColor(1, 1, 1, 1)
	for i, line in ipairs(lines) do
		love.graphics.print(line, MARGIN, top + (i - 1) * LINE)
	end
	if status then
		love.graphics.setColor(RED)
		love.graphics.print(status, MARGIN, top + #lines * LINE)
	end
	love.graphics.pop()
end

return GhostRender
