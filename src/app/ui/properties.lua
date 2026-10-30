-- The script builder's Properties section (docs/CONTEXT.md "Node"): the
-- selected primitive's dimensions and segments (src/game/builder/properties.lua)
-- as stacked entries, each a label over a full-width number box. A click on a
-- box edits it as text. Layout is pure arithmetic (testable); only draw
-- touches love.graphics.
local PropertiesStrip = {}

local LABEL_H, ROW_H, GAP = 16, 22, 6
-- A label character's width, in px, roughly the default font's.
local CHAR_WIDTH = 7

local BOX_COLOR = { 0.18, 0.19, 0.22, 1 }
local EDIT_COLOR = { 0.1, 0.1, 0.12, 1 }
local EDIT_OUTLINE = { 0.3, 0.5, 0.85, 1 }
local TEXT_COLOR = { 1, 1, 1, 1 }

local ENTRY_H = LABEL_H + ROW_H + GAP

-- The px `count` entries take.
function PropertiesStrip.height(count)
	return count * ENTRY_H
end

-- `label` cut to fit `width` px.
function PropertiesStrip.clip(label, width)
	local max = math.max(1, math.floor(width / CHAR_WIDTH))
	if #label <= max then
		return label
	end
	return label:sub(1, max - 1) .. "~"
end

-- The entries for `props` (Properties.of) stacked from (x, y), `width` px
-- wide: { { prop, x, y, width, height, labelX, labelY }, ... } top to
-- bottom; x, y, width and height are the box's.
function PropertiesStrip.fields(props, x, y, width)
	local out = {}
	for i, prop in ipairs(props) do
		local top = y + (i - 1) * ENTRY_H
		out[i] = {
			prop = prop, x = x, y = top + LABEL_H, width = width, height = ROW_H,
			labelX = x, labelY = top,
		}
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
	love.graphics.push("all")
	for _, f in ipairs(fields) do
		local open = editing and editing.key == f.prop.key
		love.graphics.setColor(TEXT_COLOR)
		love.graphics.print(PropertiesStrip.clip(f.prop.label, f.width), f.labelX, f.labelY)
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
