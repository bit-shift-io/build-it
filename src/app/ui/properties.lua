-- The script builder's properties strip (docs/CONTEXT.md "Node"): the
-- selected primitive's dimensions and segments (src/game/builder/properties.lua)
-- in a row of labelled number boxes along the top right, under the top
-- bar. A click on a box edits it as text. Layout is pure arithmetic
-- (testable); only draw touches love.graphics.
local PropertiesStrip = {}

local MARGIN, BOX_W, ROW_H, GAP, PAD = 8, 64, 22, 10, 6
-- A label character's width, in px, roughly the default font's.
local CHAR_WIDTH = 7

local PANEL_COLOR = { 0, 0, 0, 0.6 }
local BOX_COLOR = { 0.18, 0.19, 0.22, 1 }
local EDIT_COLOR = { 0.1, 0.1, 0.12, 1 }
local EDIT_OUTLINE = { 0.3, 0.5, 0.85, 1 }
local TEXT_COLOR = { 1, 1, 1, 1 }

-- The boxes for `props` (Properties.of) in a window `width` px wide, under
-- a top bar `top` px tall: { { prop, x, y, width, height, labelX }, ... }
-- left to right, the last ending a margin from the right edge; x, y,
-- width and height are the box's, labelX where its label starts.
function PropertiesStrip.fields(props, width, top)
	local total = 0
	for _, prop in ipairs(props) do
		total = total + #prop.label * CHAR_WIDTH + PAD + BOX_W + GAP
	end
	local x, y = width - MARGIN - total, top + MARGIN
	local out = {}
	for i, prop in ipairs(props) do
		local labelX = x
		x = x + #prop.label * CHAR_WIDTH + PAD
		out[i] = { prop = prop, x = x, y = y, width = BOX_W, height = ROW_H, labelX = labelX }
		x = x + BOX_W + GAP
	end
	return out
end

-- The field whose box is under screen point (x, y), or nil.
function PropertiesStrip.fieldAt(fields, x, y)
	for _, f in ipairs(fields) do
		if x >= f.x and x < f.x + f.width and y >= f.y and y < f.y + f.height then
			return f
		end
	end
	return nil
end

-- Draws `fields`; `editing` ({ key, text } or nil) is the text box open on
-- one of them.
function PropertiesStrip.draw(fields, editing)
	if #fields == 0 then
		return
	end
	love.graphics.push("all")
	local first, last = fields[1], fields[#fields]
	love.graphics.setColor(PANEL_COLOR)
	love.graphics.rectangle("fill", first.labelX - PAD, first.y - 3, last.x + last.width + PAD - first.labelX + PAD, ROW_H + 6, 4, 4)
	for _, f in ipairs(fields) do
		local open = editing and editing.key == f.prop.key
		love.graphics.setColor(TEXT_COLOR)
		love.graphics.print(f.prop.label, f.labelX, f.y + 4)
		love.graphics.setColor(open and EDIT_COLOR or BOX_COLOR)
		love.graphics.rectangle("fill", f.x, f.y, f.width, f.height, 3, 3)
		if open then
			love.graphics.setColor(EDIT_OUTLINE)
			love.graphics.rectangle("line", f.x, f.y, f.width, f.height, 3, 3)
		end
		love.graphics.setColor(TEXT_COLOR)
		love.graphics.print(open and (editing.text .. "_") or tostring(f.prop.value), f.x + 4, f.y + 4)
	end
	love.graphics.pop()
end

return PropertiesStrip
