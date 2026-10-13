-- The placement ghost (src/app/screens/world.lua): the design being placed,
-- translucent over its footprint at the pointer, tinted green when the
-- placement is valid and red when not, with its port tile markers; and the
-- placement panel, in screen space.
local Projection = require("src.game.projection")
local Placement = require("src.game.buildings.placement")
local BuildingsRender = require("src.app.render.buildings")

local GhostRender = {}

local VALID = { 0.35, 0.9, 0.45 }
local INVALID = { 0.95, 0.25, 0.2 }
local SPRITE_ALPHA = 0.75

-- ghost: WorldScreen.ghost's { request, ok, reason }. Draws in world space,
-- inside the camera.
function GhostRender.draw(ctx, ghost, zoom)
	local p = Projection.new(ctx.config)
	local req = ghost.request
	local version = req.design.versions[req.version]
	local width, depth = Placement.footprint(version, req.facing)
	local color = ghost.ok and VALID or INVALID
	local t = p.pixelsPerTile
	local x, y = Projection.worldToScreen(p, req.tileX, req.tileY, 0)

	love.graphics.push("all")
	love.graphics.setColor(color[1], color[2], color[3], 0.35)
	love.graphics.rectangle("fill", x, y, width * t, depth * t)
	for _, port in ipairs(Placement.ports(version, req.facing, req.tileX, req.tileY, ctx.config.builder)) do
		BuildingsRender.drawPort(p, port)
	end

	local sprite = BuildingsRender.sprite(ctx.config, req.design, req.version, req.facing, Projection.bakeScale(zoom or 1))
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
	love.graphics.rectangle("line", x, y, width * t, depth * t)
	love.graphics.pop()
end

local MARGIN, LINE = 8, 18

-- The placement panel, bottom-left in screen space: the library's designs
-- by number key, or while placing, what is placed and how, and `status`
-- (why the ghost or the last click is refused), in red.
--   placing: { design, version, facing } or nil; cost: { [item] = n } or nil
function GhostRender.drawPanel(library, placing, cost, status)
	local lines = {}
	if placing then
		local parts = {}
		for item, n in pairs(cost or {}) do
			table.insert(parts, n .. " " .. item)
		end
		table.sort(parts)
		table.insert(lines, string.format("Placing %s v%d, facing %s. Cost: %s", placing.design.name, placing.version, placing.facing, table.concat(parts, ", ")))
		table.insert(lines, "R turn, click place, Esc or right-click cancel")
	elseif #library.designs > 0 then
		local parts = {}
		for i, design in ipairs(library.designs) do
			if i > 9 then
				break
			end
			table.insert(parts, i .. " " .. design.name)
		end
		table.insert(lines, "Place a design: " .. table.concat(parts, "   "))
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
		love.graphics.setColor(1, 0.45, 0.4, 1)
		love.graphics.print(status, MARGIN, top + #lines * LINE)
	end
	love.graphics.pop()
end

return GhostRender
