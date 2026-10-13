-- The inventory HUD: log, stone and plank counts, top-left, in screen space.
local Inventory = require("src.game.components.inventory")

local Hud = {}

local ITEMS = { "log", "stone", "plank" }
local MARGIN, LINE = 8, 18

function Hud.draw(inventory)
	love.graphics.setColor(0, 0, 0, 0.5)
	love.graphics.rectangle("fill", MARGIN - 4, MARGIN - 4, 110, #ITEMS * LINE + 8)
	love.graphics.setColor(1, 1, 1, 1)
	for i, item in ipairs(ITEMS) do
		love.graphics.print(item .. ": " .. Inventory.count(inventory, item), MARGIN, MARGIN + (i - 1) * LINE)
	end
end

return Hud
