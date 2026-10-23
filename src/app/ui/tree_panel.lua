-- The script builder's tree panel (docs/CONTEXT.md "Node"): one row per
-- node of the scene (src/game/builder/scene.lua), indented by depth, down
-- the left of the window under the top bar. Layout is pure arithmetic
-- (testable); only draw touches love.graphics.
local Scene = require("src.game.builder.scene")

local TreePanel = {}

local MARGIN, WIDTH, ROW_H, INDENT, PAD = 8, 220, 20, 14, 6

local PANEL_COLOR = { 0, 0, 0, 0.6 }
local HOVER_COLOR = { 1, 1, 1, 0.12 }
local SELECTED_COLOR = { 0.3, 0.5, 0.85, 0.75 }
local EDIT_COLOR = { 0.1, 0.1, 0.12, 1 }
local TEXT_COLOR = { 1, 1, 1, 1 }
local LOCKED_COLOR = { 1, 0.75, 0.45, 1 }
local READ_ONLY_COLOR = { 0.6, 0.62, 0.66, 1 }

local function inside(r, x, y)
	return x >= r.x and x < r.x + r.width and y >= r.y and y < r.y + r.height
end

-- The rows of `scene`'s tree for a panel starting `top` px down:
-- { { node, depth, label, readOnly?, owner?, x, y, width, height }, ... }
-- in tree order. `expanded` (Scene.rows) maps prefab instance ids to their
-- prefabs' trees, listed read-only under them; `owner` is the instance.
function TreePanel.rows(scene, top, expanded)
	local out = {}
	for i, row in ipairs(Scene.rows(scene, expanded)) do
		out[i] = {
			node = row.node,
			depth = row.depth,
			readOnly = row.readOnly,
			owner = row.owner,
			label = Scene.label(row.node),
			x = MARGIN,
			y = top + MARGIN + PAD + (i - 1) * ROW_H,
			width = WIDTH,
			height = ROW_H,
		}
	end
	return out
end

-- The panel's rectangle around `rows` (TreePanel.rows) from `top`.
function TreePanel.bounds(rows, top)
	return { x = MARGIN, y = top + MARGIN, width = WIDTH, height = #rows * ROW_H + 2 * PAD }
end

-- The row under screen point (x, y), or nil.
function TreePanel.rowAt(rows, x, y)
	for _, row in ipairs(rows) do
		if inside(row, x, y) then
			return row
		end
	end
	return nil
end

-- Whether screen point (x, y) is on the panel.
function TreePanel.contains(rows, top, x, y)
	return inside(TreePanel.bounds(rows, top), x, y)
end

-- Draws `rows` from `top`: selected rows highlighted, the row being
-- renamed (`rename` = { id, text }, or nil) as a text box, read-only rows
-- greyed, and the panel tinted when the script is `locked`. `mouse` is { x, y } or nil.
function TreePanel.draw(rows, top, scene, rename, locked, mouse)
	local panel = TreePanel.bounds(rows, top)
	love.graphics.push("all")
	love.graphics.setColor(PANEL_COLOR)
	love.graphics.rectangle("fill", panel.x, panel.y, panel.width, panel.height, 4, 4)
	for _, row in ipairs(rows) do
		local id = row.node.id
		if not row.readOnly and Scene.isSelected(scene, id) then
			love.graphics.setColor(SELECTED_COLOR)
			love.graphics.rectangle("fill", row.x, row.y, row.width, row.height)
		elseif mouse and inside(row, mouse.x, mouse.y) then
			love.graphics.setColor(HOVER_COLOR)
			love.graphics.rectangle("fill", row.x, row.y, row.width, row.height)
		end
		local textX = row.x + PAD + row.depth * INDENT
		if rename and rename.id == id and not row.readOnly then
			love.graphics.setColor(EDIT_COLOR)
			love.graphics.rectangle("fill", textX - 2, row.y + 1, row.x + row.width - textX - PAD, row.height - 2)
			love.graphics.setColor(TEXT_COLOR)
			love.graphics.print(rename.text .. "_", textX, row.y + 3)
		else
			love.graphics.setColor(row.readOnly and READ_ONLY_COLOR or locked and LOCKED_COLOR or TEXT_COLOR)
			love.graphics.print(row.label, textX, row.y + 3)
		end
	end
	love.graphics.pop()
end

return TreePanel
