-- The script builder's Params section (docs/CONTEXT.md "Param"): one input
-- per param the design declares (src/game/script/params.lua), stacked, each
-- a label over its input. A number is a stepper (- value +) whose value box
-- edits as text; a bool's box toggles, a choice's box steps to the next
-- option, a colour's box edits as "r g b" text. Layout is pure arithmetic
-- (testable); only draw touches love.graphics.
local ParamsPanel = {}

local BUTTON_W, ROW_H, LABEL_H, GAP = 22, 22, 16, 4
-- A label character's width, in px, roughly the default font's.
local CHAR_WIDTH = 7
local ENTRY_H = LABEL_H + ROW_H + GAP + 2

local BOX_COLOR = { 0.18, 0.19, 0.22, 1 }
local EDIT_COLOR = { 0.1, 0.1, 0.12, 1 }
local EDIT_OUTLINE = { 0.3, 0.5, 0.85, 1 }
local TEXT_COLOR = { 1, 1, 1, 1 }

local function box(x, y, w)
	return { x = x, y = y, width = w, height = ROW_H }
end

-- The px `count` params take.
function ParamsPanel.height(count)
	return count * ENTRY_H
end

-- `label` cut to fit `width` px.
function ParamsPanel.clip(label, width)
	local max = math.max(1, math.floor(width / CHAR_WIDTH))
	if #label <= max then
		return label
	end
	return label:sub(1, max - 1) .. "~"
end

-- The rows for `params` (Params.collect) stacked from (x, y), `width` px
-- wide: { { param, index, labelX, labelY, y, value, minus?, plus? }, ... }
-- top to bottom; value, minus and plus are boxes { x, y, width, height },
-- minus and plus for numbers only.
function ParamsPanel.rows(params, x, y, width)
	local out = {}
	for i, param in ipairs(params) do
		local top = y + (i - 1) * ENTRY_H
		local iy = top + LABEL_H
		local r = { param = param, index = i, y = iy, labelX = x, labelY = top }
		if param.kind == "number" then
			r.minus = box(x, iy, BUTTON_W)
			r.plus = box(x + width - BUTTON_W, iy, BUTTON_W)
			r.value = box(x + BUTTON_W + GAP, iy, width - 2 * (BUTTON_W + GAP))
		else
			r.value = box(x, iy, width)
		end
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
	love.graphics.push("all")
	for _, r in ipairs(rows) do
		local open = editing and editing.index == r.index
		love.graphics.setColor(TEXT_COLOR)
		love.graphics.print(ParamsPanel.clip(r.param.label, r.value.width + (r.minus and 2 * (BUTTON_W + GAP) or 0)), r.labelX, r.labelY)
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
