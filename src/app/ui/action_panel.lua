-- The script builder's action panel (docs/CONTEXT.md "Action panel"): the
-- selection's actions as a column of buttons under the tree panel, or a
-- hint when nothing is selected. Layout is pure arithmetic (testable); only
-- draw touches love.graphics.
local ActionPanel = {}

local MARGIN, WIDTH, ROW_H, PAD, GAP = 8, 220, 22, 6, 8

ActionPanel.HINT = "Select something, or press 2 to draw."

local function inside(r, x, y)
	return x >= r.x and x < r.x + r.width and y >= r.y and y < r.y + r.height
end

-- The panel for `items` (labels, or nil for the hint) starting `treeBottom`
-- px down (the bottom of TreePanel.bounds): { x, y, width, height, hint?,
-- buttons = { { label, x, y, width, height }, ... } }.
function ActionPanel.layout(items, treeBottom)
	local y = treeBottom + GAP
	local panel = { x = MARGIN, y = y, width = WIDTH, buttons = {} }
	if not items then
		panel.hint = ActionPanel.HINT
		panel.height = ROW_H + 2 * PAD
		return panel
	end
	for i, label in ipairs(items) do
		panel.buttons[i] = {
			label = label,
			x = MARGIN,
			y = y + PAD + (i - 1) * ROW_H,
			width = WIDTH,
			height = ROW_H,
		}
	end
	panel.height = #items * ROW_H + 2 * PAD
	return panel
end

-- The label of the button under screen point (x, y), or nil.
function ActionPanel.itemAt(panel, x, y)
	for _, b in ipairs(panel.buttons) do
		if inside(b, x, y) then
			return b.label
		end
	end
	return nil
end

-- Whether screen point (x, y) is on the panel.
function ActionPanel.contains(panel, x, y)
	return inside(panel, x, y)
end

-- Draws `panel`, the button under `mouse` ({ x, y } or nil) lit.
function ActionPanel.draw(panel, mouse)
	love.graphics.push("all")
	love.graphics.setColor(0, 0, 0, 0.6)
	love.graphics.rectangle("fill", panel.x, panel.y, panel.width, panel.height, 4, 4)
	if panel.hint then
		love.graphics.setColor(0.75, 0.77, 0.8, 1)
		love.graphics.print(panel.hint, panel.x + PAD, panel.y + PAD + 3)
	end
	for _, b in ipairs(panel.buttons) do
		if mouse and inside(b, mouse.x, mouse.y) then
			love.graphics.setColor(1, 1, 1, 0.15)
			love.graphics.rectangle("fill", b.x, b.y, b.width, b.height)
		end
		love.graphics.setColor(1, 1, 1, 1)
		love.graphics.print(b.label, b.x + PAD, b.y + 4)
	end
	love.graphics.pop()
end

return ActionPanel
