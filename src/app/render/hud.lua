-- The inventory HUD: log, stone and plank counts, top-left, in screen space,
-- and what E does on an output port tile.
local Inventory = require("src.game.components.inventory")
local Aura = require("src.game.components.aura")
local Storage = require("src.game.components.storage")

local Hud = {}

local ITEMS = { "log", "stone", "plank" }
local MARGIN, LINE = 8, 18

-- port: the output port the player stands on, or nil.
function Hud.draw(inventory, port, aura)
	love.graphics.setColor(0, 0, 0, 0.5)
	love.graphics.rectangle("fill", MARGIN - 4, MARGIN - 4, 110, #ITEMS * LINE + 8)
	love.graphics.setColor(1, 1, 1, 1)
	for i, item in ipairs(ITEMS) do
		love.graphics.print(item .. ": " .. Inventory.count(inventory, item), MARGIN, MARGIN + (i - 1) * LINE)
	end
	if aura and (aura.walkSpeed > 0 or aura.harvestRate > 0) then
		local top = MARGIN + #ITEMS * LINE + 8 + (port and LINE + 12 or 0)
		local lines = {}
		for _, name in ipairs(Aura.NAMES) do
			if aura[name] > 0 then
				table.insert(lines, string.format("%s +%d%%", Aura.LABELS[name], math.floor(aura[name] * 100 + 0.5)))
			end
		end
		love.graphics.setColor(0, 0, 0, 0.5)
		love.graphics.rectangle("fill", MARGIN - 4, top - 4, 160, #lines * LINE + 8)
		love.graphics.setColor(1, 1, 1, 1)
		for i, text in ipairs(lines) do
			love.graphics.print(text, MARGIN, top + (i - 1) * LINE)
		end
	end
	if port then
		local n = Storage.total(port.buffer)
		local text = n > 0 and ("E: collect " .. n .. " items") or "Output port: empty"
		local top = MARGIN + #ITEMS * LINE + 8
		love.graphics.setColor(0, 0, 0, 0.5)
		love.graphics.rectangle("fill", MARGIN - 4, top - 4, 160, LINE + 8)
		love.graphics.setColor(1, 1, 1, 1)
		love.graphics.print(text, MARGIN, top)
	end
end

return Hud
