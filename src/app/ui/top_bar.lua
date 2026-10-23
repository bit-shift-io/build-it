-- The script builder's numbered top bar (docs/CONTEXT.md "Builder"): a
-- row of slots 1..n along the top of the window, each holding a tool or
-- empty, picked by click or by its number key. Layout is pure arithmetic
-- (testable); only draw touches love.graphics.
local TopBar = {}

local SLOT_GAP = 4
local SLOT_INSET = 4
-- A label character's width, in px, roughly the default font's.
local CHAR_WIDTH = 7

local BAR_BACKGROUND = { 0.13, 0.14, 0.16, 1 }
local SLOT_COLOR = { 0.24, 0.26, 0.3, 1 }
local ACTIVE_COLOR = { 0.3, 0.5, 0.85, 1 }
local TEXT_COLOR = { 0.92, 0.92, 0.92, 1 }
local EMPTY_TEXT_COLOR = { 0.5, 0.5, 0.52, 1 }

-- `count` slots for a bar `height` px tall, left to right, with the tools
-- in `tools` ({ [slot] = { id, label } }): { { x, y, width, height,
-- number, tool }, ... }; tool is nil for an empty slot. A slot with a tool
-- widens to fit its label.
function TopBar.slots(height, count, tools)
	local size = height - 2 * SLOT_INSET
	local slots, x = {}, SLOT_INSET
	for i = 1, count do
		local tool = tools[i]
		local width = tool and math.max(size, (#tool.label + 3) * CHAR_WIDTH) or size
		slots[i] = { x = x, y = SLOT_INSET, width = width, height = size, number = i, tool = tool }
		x = x + width + SLOT_GAP
	end
	return slots
end

-- The slot under screen point (x, y), or nil.
function TopBar.slotAt(slots, x, y)
	for _, s in ipairs(slots) do
		if x >= s.x and x < s.x + s.width and y >= s.y and y < s.y + s.height then
			return s
		end
	end
	return nil
end

-- Draws the bar `height` px tall across a window `width` px wide, the
-- slot holding tool `active` (an id) highlighted.
function TopBar.draw(slots, active, width, height)
	love.graphics.push("all")
	love.graphics.setColor(BAR_BACKGROUND)
	love.graphics.rectangle("fill", 0, 0, width, height)
	for _, slot in ipairs(slots) do
		local on = slot.tool and slot.tool.id == active
		love.graphics.setColor(on and ACTIVE_COLOR or SLOT_COLOR)
		love.graphics.rectangle("fill", slot.x, slot.y, slot.width, slot.height, 4, 4)
		love.graphics.setColor(slot.tool and TEXT_COLOR or EMPTY_TEXT_COLOR)
		local label = slot.tool and (slot.number .. " " .. slot.tool.label) or tostring(slot.number)
		love.graphics.print(label, slot.x + 4, slot.y + 2)
	end
	love.graphics.pop()
end

return TopBar
