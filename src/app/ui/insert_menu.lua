-- The Insert tool's menu (docs/CONTEXT.md "Prefab", "Role prefab"): a
-- column of the items it offers (src/game/builder/insert.lua) hanging under
-- its top bar slot, primitives first, then prefabs. Layout is pure
-- arithmetic (testable); only draw touches love.graphics.
local InsertMenu = {}

local WIDTH, ROW_H, PAD, GAP = 150, 20, 6, 4

local BACKGROUND = { 0, 0, 0, 0.85 }
local HOVER_COLOR = { 1, 1, 1, 0.15 }
local ARMED_COLOR = { 0.3, 0.5, 0.85, 0.75 }
local TEXT_COLOR = { 1, 1, 1, 1 }
local PREFAB_COLOR = { 0.75, 0.85, 1, 1 }

local function inside(r, x, y)
	return x >= r.x and x < r.x + r.width and y >= r.y and y < r.y + r.height
end

-- The rows of `items` under top bar slot `slot` (TopBar.slots):
-- { { item, x, y, width, height }, ... } top to bottom.
function InsertMenu.rows(items, slot)
	local rows = {}
	for i, item in ipairs(items) do
		rows[i] = { item = item, x = slot.x, y = slot.y + slot.height + GAP + (i - 1) * ROW_H, width = WIDTH, height = ROW_H }
	end
	return rows
end

-- The row under screen point (x, y), or nil.
function InsertMenu.rowAt(rows, x, y)
	for _, row in ipairs(rows) do
		if inside(row, x, y) then
			return row
		end
	end
	return nil
end

-- Draws `rows`, the row holding item `armed` marked and the one under
-- `mouse` ({ x, y } or nil) lit.
function InsertMenu.draw(rows, armed, mouse)
	if #rows == 0 then
		return
	end
	love.graphics.push("all")
	local first = rows[1]
	love.graphics.setColor(BACKGROUND)
	love.graphics.rectangle("fill", first.x, first.y, WIDTH, #rows * ROW_H)
	for _, row in ipairs(rows) do
		if row.item == armed then
			love.graphics.setColor(ARMED_COLOR)
			love.graphics.rectangle("fill", row.x, row.y, row.width, row.height)
		elseif mouse and inside(row, mouse.x, mouse.y) then
			love.graphics.setColor(HOVER_COLOR)
			love.graphics.rectangle("fill", row.x, row.y, row.width, row.height)
		end
		love.graphics.setColor(row.item.prefab and PREFAB_COLOR or TEXT_COLOR)
		love.graphics.print(row.item.label, row.x + PAD, row.y + 3)
	end
	love.graphics.pop()
end

return InsertMenu
