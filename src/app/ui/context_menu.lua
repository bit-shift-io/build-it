-- A right-click context menu: a column of entries opened at the pointer.
-- Layout is pure arithmetic (testable); only draw touches love.graphics.
local ContextMenu = {}

local WIDTH, ROW_H, PAD = 130, 22, 6

local function inside(r, x, y)
	return x >= r.x and x < r.x + r.width and y >= r.y and y < r.y + r.height
end

-- A menu of `items` (labels, top to bottom) opened at screen (x, y).
function ContextMenu.open(x, y, items)
	return { x = x, y = y, items = items }
end

-- The rectangle of entry i.
function ContextMenu.row(menu, i)
	return { x = menu.x, y = menu.y + (i - 1) * ROW_H, width = WIDTH, height = ROW_H }
end

-- The label of the entry under screen point (x, y), or nil.
function ContextMenu.itemAt(menu, x, y)
	for i, item in ipairs(menu.items) do
		if inside(ContextMenu.row(menu, i), x, y) then
			return item
		end
	end
	return nil
end

-- Draws `menu`, the entry under `mouse` ({ x, y } or nil) lit.
function ContextMenu.draw(menu, mouse)
	love.graphics.push("all")
	love.graphics.setColor(0, 0, 0, 0.85)
	love.graphics.rectangle("fill", menu.x, menu.y, WIDTH, #menu.items * ROW_H)
	for i, item in ipairs(menu.items) do
		local r = ContextMenu.row(menu, i)
		if mouse and inside(r, mouse.x, mouse.y) then
			love.graphics.setColor(1, 1, 1, 0.15)
			love.graphics.rectangle("fill", r.x, r.y, r.width, r.height)
		end
		love.graphics.setColor(1, 1, 1, 1)
		love.graphics.print(item, r.x + PAD, r.y + 4)
	end
	love.graphics.pop()
end

return ContextMenu
