-- Draws each character as a placeholder square centred on its position.
local CharacterRender = {}

local FILL = { 0.95, 0.75, 0.25, 1 }

function CharacterRender.draw(ctx)
	love.graphics.setColor(FILL)
	for _, c in ipairs(ctx.pools.characters) do
		local half = c.size / 2
		love.graphics.rectangle("fill", c.x - half, c.y - half, c.size, c.size)
	end
end

return CharacterRender
