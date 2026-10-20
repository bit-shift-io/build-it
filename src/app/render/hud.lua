-- The HUD, top-left, in screen space: the player's log, stone and plank
-- counts, the storage totals across every storage facility below them
-- (what placement may still spend, with what construction sites reserved
-- beside it),
-- what E does on the port underfoot or faced, the aura the player stands in, and
-- "Hungry" or "Starving" while it applies (F eats).
local Inventory = require("src.game.components.inventory")
local Aura = require("src.game.components.aura")
local Storage = require("src.game.components.storage")
local Ports = require("src.game.components.ports")

local Hud = {}

local ITEMS = { "log", "stone", "plank", "berry", "meat", "fish" }
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

-- Pure line builders (no love.*): only non-zero items are listed.
function Hud.inventoryLines(inventory)
	local lines = {}
	for _, item in ipairs(ITEMS) do
		local n = Inventory.count(inventory, item)
		if n > 0 then
			table.insert(lines, item .. ": " .. n)
		end
	end
	return lines
end

function Hud.storageLines(stock, reserved, fill)
	local lines = { fill and ("Storage " .. fill .. "%") or "Storage" }
	for _, item in ipairs(ITEMS) do
		local n = stock[item] or 0
		local held = reserved and reserved[item] or 0
		if n > 0 or held > 0 then
			local line = item .. ": " .. n
			if held > 0 then
				line = line .. " (" .. held .. " reserved)"
			end
			table.insert(lines, line)
		end
	end
	return lines
end

-- The hint line for the port E works on. An input port offers delivery when
-- the inventory holds something its building accepts (food: config.food).
function Hud.portHint(port, inventory, food)
	if port.kind == "input" then
		for item, n in pairs(inventory.counts) do
			if n > 0 and Ports.accepts(port.building, item, food) then
				return "E: deliver"
			end
		end
		return "Input port: nothing accepted"
	end
	local n = Storage.total(port.buffer)
	return n > 0 and ("E: collect " .. n .. " items") or "Output port: empty"
end

-- inventory: the player's. stock: the storage totals ({ [item] = n },
-- StorageFacility.totals). port: the port E works on (CharacterSystem.portInUse), or
-- nil. aura: the aura at the player. reserved: what construction sites
-- claimed ({ [item] = n }, StorageFacility.claimed), or nil. fill: the
-- colony-wide storage percent (StorageFacility.totalFill), or nil. hunger:
-- the player's warning (Status.hunger), or nil. food: config.food.
function Hud.draw(inventory, stock, port, aura, reserved, fill, hunger, food)
	local lines = Hud.inventoryLines(inventory)
	local top = MARGIN
	if #lines > 0 then
		top = panel(lines, top, 110)
	end
	lines = Hud.storageLines(stock, reserved, fill)
	local width = 110
	for _, line in ipairs(lines) do
		if line:find("reserved", 1, true) then
			width = 200
		end
	end
	top = panel(lines, top, width)
	if hunger then
		top = panel({ hunger .. " (F: eat)" }, top, 130)
	end
	if port then
		top = panel({ Hud.portHint(port, inventory, food) }, top, 160)
	end
	if aura then
		lines = Aura.lines(aura)
		if #lines > 0 then
			panel(lines, top, 160)
		end
	end
end

-- The "Settings (O)" button, top-right of a window `w` px wide:
-- { x, y, width, height }. Clicking it opens the in-world settings overlay.
function Hud.settingsButton(w)
	return { x = w - 118, y = MARGIN, width = 110, height = 26 }
end

function Hud.drawSettingsButton(w, mouse)
	local b = Hud.settingsButton(w)
	local hot = mouse and mouse.x >= b.x and mouse.x < b.x + b.width and mouse.y >= b.y and mouse.y < b.y + b.height
	love.graphics.push("all")
	love.graphics.setColor(hot and 0.35 or 0.22, hot and 0.55 or 0.24, hot and 0.8 or 0.27, 0.9)
	love.graphics.rectangle("fill", b.x, b.y, b.width, b.height, 4, 4)
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.printf("Settings (O)", b.x, b.y + (b.height - love.graphics.getFont():getHeight()) / 2, b.width, "center")
	love.graphics.pop()
end

-- The frame shown before a view's first bake: the bake runs on the next
-- draw, so this message is on screen while it works.
function Hud.drawBaking(w, h)
	love.graphics.push("all")
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.printf("Baking\226\128\166", 0, h / 2 - love.graphics.getFont():getHeight() / 2, w, "center")
	love.graphics.pop()
end

return Hud
