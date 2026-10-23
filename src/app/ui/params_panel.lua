-- The script builder's params panel (docs/CONTEXT.md "Param"): one input
-- per param the design declares (src/game/script/params.lua), a column of
-- labelled rows down the right edge under the top bar. A number is a
-- stepper (- value +) whose value box edits as text; a bool's box toggles,
-- a choice's box steps to the next option, a colour's box edits as
-- "r g b" text. Layout is pure arithmetic (testable); only draw touches
-- love.graphics.
local ParamsPanel = {}

local MARGIN, LABEL_W, BOX_W, BUTTON_W, ROW_H, GAP, PAD = 8, 110, 72, 22, 22, 4, 6

local PANEL_COLOR = { 0, 0, 0, 0.6 }
local BOX_COLOR = { 0.18, 0.19, 0.22, 1 }
local EDIT_COLOR = { 0.1, 0.1, 0.12, 1 }
local EDIT_OUTLINE = { 0.3, 0.5, 0.85, 1 }
local TEXT_COLOR = { 1, 1, 1, 1 }

local function box(x, y, w)
	return { x = x, y = y, width = w, height = ROW_H }
end

-- The rows for `params` (Params.collect) in a window `width` px wide,
-- under a top bar `top` px tall: { { param, index, labelX, y, value,
-- minus?, plus? }, ... } top to bottom; value, minus and plus are boxes
-- { x, y, width, height }, minus and plus for numbers only.
function ParamsPanel.rows(params, width, top)
	local out = {}
	local right = width - MARGIN
	for i, param in ipairs(params) do
		local y = top + MARGIN + (i - 1) * (ROW_H + GAP)
		local r = { param = param, index = i, y = y }
		if param.kind == "number" then
			r.plus = box(right - BUTTON_W, y, BUTTON_W)
			r.value = box(r.plus.x - GAP - BOX_W, y, BOX_W)
			r.minus = box(r.value.x - GAP - BUTTON_W, y, BUTTON_W)
		else
			r.value = box(right - BUTTON_W - GAP - BOX_W - GAP - BUTTON_W, y, BUTTON_W + GAP + BOX_W + GAP + BUTTON_W)
		end
		r.labelX = right - (BUTTON_W + GAP) * 2 - BOX_W - PAD - LABEL_W
		out[i] = r
	end
	return out
end

local function inside(b, x, y)
	return b and x >= b.x and x < b.x + b.width and y >= b.y and y < b.y + b.height
end

-- The row and part ("minus", "plus" or "value") under screen point (x, y),
-- or nil.
function ParamsPanel.hit(rows, x, y)
	for _, r in ipairs(rows) do
		for _, part in ipairs({ "minus", "plus", "value" }) do
			if inside(r[part], x, y) then
				return r, part
			end
		end
	end
	return nil
end

-- Whether screen point (x, y) is on the panel.
function ParamsPanel.contains(rows, x, y)
	for _, r in ipairs(rows) do
		if x >= r.labelX - PAD and y >= r.y - GAP / 2 and y < r.y + ROW_H + GAP / 2 then
			return true
		end
	end
	return false
end

-- A param's value as the panel shows it.
function ParamsPanel.show(param)
	local v = param.value
	if param.kind == "color" then
		return string.format("%.2f %.2f %.2f", v[1], v[2], v[3])
	end
	return tostring(v)
end

-- Draws `rows`; `editing` ({ index, text } or nil) is the text box open on
-- one of them.
function ParamsPanel.draw(rows, editing)
	if #rows == 0 then
		return
	end
	love.graphics.push("all")
	local last = rows[#rows]
	local left = last.labelX - PAD
	local right = last.value.x + last.value.width + (last.plus and (GAP + BUTTON_W) or 0) + PAD
	love.graphics.setColor(PANEL_COLOR)
	love.graphics.rectangle("fill", left, rows[1].y - 3, right - left, last.y + ROW_H + 3 - (rows[1].y - 3), 4, 4)
	for _, r in ipairs(rows) do
		local open = editing and editing.index == r.index
		love.graphics.setColor(TEXT_COLOR)
		love.graphics.print(r.param.label, r.labelX, r.y + 4)
		for _, part in ipairs({ "minus", "value", "plus" }) do
			local b = r[part]
			if b then
				local editingThis = open and part == "value"
				love.graphics.setColor(editingThis and EDIT_COLOR or BOX_COLOR)
				love.graphics.rectangle("fill", b.x, b.y, b.width, b.height, 3, 3)
				if editingThis then
					love.graphics.setColor(EDIT_OUTLINE)
					love.graphics.rectangle("line", b.x, b.y, b.width, b.height, 3, 3)
				end
				local label = part == "minus" and "-" or part == "plus" and "+"
					or editingThis and (editing.text .. "_") or ParamsPanel.show(r.param)
				if part == "value" and r.param.kind == "color" and not editingThis then
					local c = r.param.value
					love.graphics.setColor(c[1], c[2], c[3], 1)
					love.graphics.rectangle("fill", b.x + b.width - b.height + 3, b.y + 3, b.height - 6, b.height - 6)
				end
				love.graphics.setColor(TEXT_COLOR)
				love.graphics.print(label, b.x + 4, b.y + 4)
			end
		end
	end
	love.graphics.pop()
end

return ParamsPanel
