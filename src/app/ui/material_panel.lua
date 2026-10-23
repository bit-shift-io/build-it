-- The script builder's material panel (docs/CONTEXT.md "Material",
-- "Texture variant"): a column under its top bar slot with a row per
-- material, a row per texture variant of the material shown, and - / +
-- steppers for the texture's scale and rotation. Layout and what a click
-- picks are pure arithmetic (testable); only draw touches love.graphics.
--
--   row = { kind = "name" | "variant" | "scale" | "rotation", value, label,
--           x, y, width, height, minus?, plus? }   minus/plus: stepper boxes
local MaterialPanel = {}

local WIDTH, ROW_H, PAD, GAP, BOX_W = 150, 20, 6, 4, 20

-- How far one - or + click steps the texture scale and rotation (degrees).
MaterialPanel.SCALE_STEP = 0.25
MaterialPanel.ROTATION_STEP = 15

local BACKGROUND = { 0, 0, 0, 0.85 }
local HOVER_COLOR = { 1, 1, 1, 0.15 }
local CHOSEN_COLOR = { 0.3, 0.5, 0.85, 0.75 }
local BOX_COLOR = { 0.24, 0.26, 0.3, 1 }
local TEXT_COLOR = { 1, 1, 1, 1 }
local HEADING_COLOR = { 0.75, 0.85, 1, 1 }

local function inside(r, x, y)
	return x >= r.x and x < r.x + r.width and y >= r.y and y < r.y + r.height
end

local function capitalised(s)
	return s:sub(1, 1):upper() .. s:sub(2)
end

-- `x` written short: no trailing zeros.
local function short(x)
	return (string.format("%.2f", x):gsub("%.?0+$", ""))
end

-- The panel's rows for `material` ({ name, variant, scale, rotation }) out
-- of `materials` (config.materials), under top bar slot `slot`
-- (TopBar.slots), top to bottom.
function MaterialPanel.rows(material, materials, slot)
	local rows = {}
	local function add(row)
		row.x, row.y = slot.x, slot.y + slot.height + GAP + #rows * ROW_H
		row.width, row.height = WIDTH, ROW_H
		rows[#rows + 1] = row
		return row
	end
	local names = {}
	for name in pairs(materials) do
		names[#names + 1] = name
	end
	table.sort(names)
	for _, name in ipairs(names) do
		add({ kind = "name", value = name, label = capitalised(name) })
	end
	for _, variant in ipairs(materials[material.name].variants) do
		add({ kind = "variant", value = variant, label = "  " .. variant })
	end
	local steppers = {
		{ kind = "scale", value = material.scale, label = "Scale " .. short(material.scale) },
		{ kind = "rotation", value = material.rotation, label = "Rotation " .. short(material.rotation) },
	}
	for _, s in ipairs(steppers) do
		local row = add(s)
		local right = row.x + row.width - PAD
		row.plus = { x = right - BOX_W, y = row.y + 2, width = BOX_W, height = ROW_H - 4 }
		row.minus = { x = right - 2 * BOX_W - GAP, y = row.y + 2, width = BOX_W, height = ROW_H - 4 }
	end
	return rows
end

-- The row under screen point (x, y) and, on a stepper, which box ("minus"
-- or "plus"); nil when on none.
function MaterialPanel.hit(rows, x, y)
	for _, row in ipairs(rows or {}) do
		if inside(row, x, y) then
			if row.minus and inside(row.minus, x, y) then
				return row, "minus"
			elseif row.plus and inside(row.plus, x, y) then
				return row, "plus"
			end
			return row, nil
		end
	end
	return nil
end

-- The material a click on `row` (and stepper box `part`) makes of
-- `material`, out of `materials`; nil when the click changes nothing. A new
-- material starts on its first variant.
function MaterialPanel.choose(material, materials, row, part)
	local out = { name = material.name, variant = material.variant, scale = material.scale, rotation = material.rotation }
	if row.kind == "name" then
		if row.value == material.name then
			return nil
		end
		out.name, out.variant = row.value, materials[row.value].variants[1]
	elseif row.kind == "variant" then
		if row.value == material.variant then
			return nil
		end
		out.variant = row.value
	elseif part then
		local dir = part == "plus" and 1 or -1
		if row.kind == "scale" then
			out.scale = math.max(MaterialPanel.SCALE_STEP, material.scale + dir * MaterialPanel.SCALE_STEP)
			if out.scale == material.scale then
				return nil
			end
		else
			out.rotation = (material.rotation + dir * MaterialPanel.ROTATION_STEP) % 360
		end
	else
		return nil
	end
	return out
end

-- Draws `rows` for `material`, its name and variant marked and the row
-- under `mouse` ({ x, y } or nil) lit.
function MaterialPanel.draw(rows, material, mouse)
	if not rows or #rows == 0 then
		return
	end
	love.graphics.push("all")
	local first = rows[1]
	love.graphics.setColor(BACKGROUND)
	love.graphics.rectangle("fill", first.x, first.y, WIDTH, #rows * ROW_H)
	for _, row in ipairs(rows) do
		local chosen = (row.kind == "name" and row.value == material.name)
			or (row.kind == "variant" and row.value == material.variant)
		if chosen then
			love.graphics.setColor(CHOSEN_COLOR)
			love.graphics.rectangle("fill", row.x, row.y, row.width, row.height)
		elseif mouse and inside(row, mouse.x, mouse.y) then
			love.graphics.setColor(HOVER_COLOR)
			love.graphics.rectangle("fill", row.x, row.y, row.width, row.height)
		end
		love.graphics.setColor(row.kind == "name" and HEADING_COLOR or TEXT_COLOR)
		love.graphics.print(row.label, row.x + PAD, row.y + 3)
		for _, part in ipairs({ "minus", "plus" }) do
			local box = row[part]
			if box then
				love.graphics.setColor(BOX_COLOR)
				love.graphics.rectangle("fill", box.x, box.y, box.width, box.height, 3, 3)
				love.graphics.setColor(TEXT_COLOR)
				love.graphics.printf(part == "plus" and "+" or "-", box.x, box.y + 1, box.width, "center")
			end
		end
	end
	love.graphics.pop()
end

return MaterialPanel
