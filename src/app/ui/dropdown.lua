-- A dropdown: a closed box showing the current value and a down arrow; open,
-- a list of options under it (over the window's bottom edge, above it).
-- Layout and hits are pure arithmetic (testable); only draw touches
-- love.graphics.
--
--   layout = { box, open, list?, items? }   box = { x, y, width, height }
--   item = { option, x, y, width, height }  option = { value, label }
local Dropdown = {}

local ITEM_H, PAD = 20, 6

local BACKGROUND = { 0.1, 0.11, 0.14, 0.97 }
local BOX_COLOR = { 0.24, 0.26, 0.3, 1 }
local HOVER_COLOR = { 1, 1, 1, 0.15 }
local CHOSEN_COLOR = { 0.3, 0.5, 0.85, 0.75 }
local TEXT_COLOR = { 1, 1, 1, 1 }

local function inside(r, x, y)
	return x >= r.x and x < r.x + r.width and y >= r.y and y < r.y + r.height
end

-- The layout of the dropdown at `box`; with `open` its list under the box,
-- or above it when it would run past `windowHeight`.
function Dropdown.layout(box, options, open, windowHeight)
	local layout = { box = box, open = open and true or false }
	if open then
		local height = #options * ITEM_H
		local y = box.y + box.height
		if windowHeight and y + height > windowHeight and box.y - height >= 0 then
			y = box.y - height
		end
		layout.list = { x = box.x, y = y, width = box.width, height = height }
		layout.items = {}
		for i, option in ipairs(options) do
			layout.items[i] = { option = option, x = box.x, y = y + (i - 1) * ITEM_H, width = box.width, height = ITEM_H }
		end
	end
	return layout
end

-- What screen point (x, y) is on: "box" (the closed box), "option" and the
-- option (an open list's item), or nil.
function Dropdown.hit(layout, x, y)
	if not layout then
		return nil
	end
	for _, item in ipairs(layout.items or {}) do
		if inside(item, x, y) then
			return "option", item.option
		end
	end
	if inside(layout.box, x, y) then
		return "box"
	end
	return nil
end

-- Whether (x, y) is on the open list.
function Dropdown.contains(layout, x, y)
	return layout ~= nil and layout.list ~= nil and inside(layout.list, x, y)
end

-- Draws the closed box with `label`.
function Dropdown.drawBox(layout, label)
	local b = layout.box
	love.graphics.push("all")
	love.graphics.setColor(BOX_COLOR)
	love.graphics.rectangle("fill", b.x, b.y, b.width, b.height, 3, 3)
	love.graphics.setColor(TEXT_COLOR)
	love.graphics.print(label, b.x + PAD, b.y + 3)
	love.graphics.printf("▾", b.x, b.y + 3, b.width - PAD, "right")
	love.graphics.pop()
end

-- Draws the open list, `chosen` (an option value) marked and the item under
-- `mouse` lit.
function Dropdown.draw(layout, chosen, mouse)
	if not layout or not layout.list then
		return
	end
	local l = layout.list
	love.graphics.push("all")
	love.graphics.setColor(BACKGROUND)
	love.graphics.rectangle("fill", l.x, l.y, l.width, l.height)
	for _, item in ipairs(layout.items) do
		if item.option.value == chosen then
			love.graphics.setColor(CHOSEN_COLOR)
			love.graphics.rectangle("fill", item.x, item.y, item.width, item.height)
		elseif mouse and inside(item, mouse.x, mouse.y) then
			love.graphics.setColor(HOVER_COLOR)
			love.graphics.rectangle("fill", item.x, item.y, item.width, item.height)
		end
		love.graphics.setColor(TEXT_COLOR)
		love.graphics.print(item.option.label, item.x + PAD, item.y + 3)
	end
	love.graphics.setColor(BOX_COLOR)
	love.graphics.rectangle("line", l.x, l.y, l.width, l.height)
	love.graphics.pop()
end

return Dropdown
