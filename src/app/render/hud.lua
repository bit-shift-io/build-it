-- The HUD, top-left, in screen space: the player's log, stone and plank
-- counts, the storage totals across every storage facility below them
-- (what placement may still spend, with what construction sites reserved
-- beside it),
-- what E does on an output port tile, and the aura the player stands in.
local Inventory = require("src.game.components.inventory")
local Aura = require("src.game.components.aura")
local Storage = require("src.game.components.storage")

local Hud = {}

local ITEMS = { "log", "stone", "plank" }
local MARGIN, LINE = 8, 18

-- A dark panel of `lines` from `top`; returns the top of the next panel.
local function panel(lines, top, width)
	love.graphics.setColor(0, 0, 0, 0.5)
	love.graphics.rectangle("fill", MARGIN - 4, top - 4, width, #lines * LINE + 8)
	love.graphics.setColor(1, 1, 1, 1)
	for i, text in ipairs(lines) do
		love.graphics.print(text, MARGIN, top + (i - 1) * LINE)
	end
	return top + #lines * LINE + 12
end

-- inventory: the player's. stock: the storage totals ({ [item] = n },
-- StorageFacility.totals). port: the output port the player stands on, or
-- nil. aura: the aura at the player. reserved: what construction sites
-- claimed ({ [item] = n }, StorageFacility.claimed), or nil.
function Hud.draw(inventory, stock, port, aura, reserved)
	local lines = {}
	for _, item in ipairs(ITEMS) do
		table.insert(lines, item .. ": " .. Inventory.count(inventory, item))
	end
	local top = panel(lines, MARGIN, 110)
	lines = { "Storage" }
	local width = 110
	for _, item in ipairs(ITEMS) do
		local line = item .. ": " .. (stock[item] or 0)
		local held = reserved and reserved[item] or 0
		if held > 0 then
			line = line .. " (" .. held .. " reserved)"
			width = 200
		end
		table.insert(lines, line)
	end
	top = panel(lines, top, width)
	if port then
		local n = Storage.total(port.buffer)
		top = panel({ n > 0 and ("E: collect " .. n .. " items") or "Output port: empty" }, top, 160)
	end
	if aura and (aura.walkSpeed > 0 or aura.harvestRate > 0) then
		lines = {}
		for _, name in ipairs(Aura.NAMES) do
			if aura[name] > 0 then
				table.insert(lines, string.format("%s +%d%%", Aura.LABELS[name], math.floor(aura[name] * 100 + 0.5)))
			end
		end
		panel(lines, top, 160)
	end
end

return Hud
