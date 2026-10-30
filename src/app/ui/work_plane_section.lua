-- The script builder column's Work plane section (docs/CONTEXT.md "Work
-- plane"): buttons for Ground, XY, XZ, YZ and Pick face with the current one
-- marked, and on an axis plane a Height - / + stepper. Layout and what a
-- click picks are pure arithmetic (testable); only draw touches
-- love.graphics.
--
--   button = { plane = "Ground" | "XY" | "XZ" | "YZ" | "Face", label, x, y,
--              width, height }
--   layout = { buttons, stepper? = { label, minus, plus } }
local WorkPlaneSection = {}

local ROW_H, GAP, BOX_W = 22, 4, 20

-- The planes that sit at a height.
local AXIS = { XY = true, XZ = true, YZ = true }

local BOX_COLOR = { 0.24, 0.26, 0.3, 1 }
local CURRENT_COLOR = { 0.3, 0.5, 0.85, 0.9 }
local TEXT_COLOR = { 1, 1, 1, 1 }

local function inside(r, x, y)
	return x >= r.x and x < r.x + r.width and y >= r.y and y < r.y + r.height
end

-- The px the section takes for plane `name`.
function WorkPlaneSection.height(name)
	return (AXIS[name] and 3 or 2) * ROW_H
end

-- The section's layout in `content` ({ x, y, width }) for the current plane
-- `name` at `height` tiles.
function WorkPlaneSection.layout(name, height, content)
	local buttons = {}
	local small = { { "Ground", "Ground" }, { "XY", "XY" }, { "XZ", "XZ" }, { "YZ", "YZ" } }
	local w = (content.width - 3 * GAP) / 4
	for i, b in ipairs(small) do
		buttons[i] = {
			plane = b[1], label = b[2], current = b[1] == name,
			x = content.x + (i - 1) * (w + GAP), y = content.y + 1, width = w, height = ROW_H - 2,
		}
	end
	buttons[5] = {
		plane = "Face", label = "Pick face", current = name == "Face",
		x = content.x, y = content.y + ROW_H + 1, width = content.width, height = ROW_H - 2,
	}
	local out = { buttons = buttons }
	if AXIS[name] then
		local y = content.y + 2 * ROW_H
		local right = content.x + content.width
		out.stepper = {
			label = "Height " .. (string.format("%.2f", height):gsub("%.?0+$", "")),
			x = content.x, y = y, width = content.width, height = ROW_H,
			plus = { x = right - BOX_W, y = y + 2, width = BOX_W, height = ROW_H - 4 },
			minus = { x = right - 2 * BOX_W - GAP, y = y + 2, width = BOX_W, height = ROW_H - 4 },
		}
	end
	return out
end

-- What screen point (x, y) hits: { plane = name } on a button, { step = -1 |
-- 1 } on a stepper box, or nil.
function WorkPlaneSection.hit(layout, x, y)
	if not layout then
		return nil
	end
	for _, b in ipairs(layout.buttons) do
		if inside(b, x, y) then
			return { plane = b.plane }
		end
	end
	local s = layout.stepper
	if s then
		if inside(s.minus, x, y) then
			return { step = -1 }
		elseif inside(s.plus, x, y) then
			return { step = 1 }
		end
	end
	return nil
end

-- Draws `layout`.
function WorkPlaneSection.draw(layout)
	if not layout then
		return
	end
	love.graphics.push("all")
	for _, b in ipairs(layout.buttons) do
		love.graphics.setColor(b.current and CURRENT_COLOR or BOX_COLOR)
		love.graphics.rectangle("fill", b.x, b.y, b.width, b.height, 3, 3)
		love.graphics.setColor(TEXT_COLOR)
		love.graphics.printf(b.label, b.x, b.y + 3, b.width, "center")
	end
	local s = layout.stepper
	if s then
		love.graphics.setColor(TEXT_COLOR)
		love.graphics.print(s.label, s.x + 6, s.y + 3)
		for _, part in ipairs({ "minus", "plus" }) do
			local box = s[part]
			love.graphics.setColor(BOX_COLOR)
			love.graphics.rectangle("fill", box.x, box.y, box.width, box.height, 3, 3)
			love.graphics.setColor(TEXT_COLOR)
			love.graphics.printf(part == "plus" and "+" or "-", box.x, box.y + 1, box.width, "center")
		end
	end
	love.graphics.pop()
end

return WorkPlaneSection
