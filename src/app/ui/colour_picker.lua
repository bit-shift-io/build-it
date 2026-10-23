-- A colour picker (docs/CONTEXT.md "Team palette"): labelled sections of
-- swatches, up to PER_ROW a row. The script builder shows the team slots,
-- the preset colours and the recent picks; Settings shows the presets once
-- per team colour. A swatch's colour is a node colour: { r, g, b } or a
-- team slot name, drawn in the palette given. Layout and what a click picks
-- are pure arithmetic; only draw touches love.graphics.
--
--   section = { id, label, colors }
--   layout  = { x, y, width, height,
--               labels = { { text, x, y } },
--               swatches = { { section = <id>, color, x, y, width, height } } }
local Palette = require("src.game.palette")
local RecentColours = require("src.game.builder.recent_colours")

local ColourPicker = {}

-- Swatch size, the gap between swatches, padding and a label's height, px.
local SIZE, GAP, PAD, LABEL_H = 18, 4, 6, 16
ColourPicker.PER_ROW = 8

-- The literal colours on offer: two rows of eight.
ColourPicker.PRESETS = {
	{ 0.75, 0.22, 0.18 }, { 0.9, 0.45, 0.15 }, { 0.95, 0.78, 0.2 }, { 0.45, 0.7, 0.25 },
	{ 0.2, 0.55, 0.35 }, { 0.2, 0.6, 0.7 }, { 0.2, 0.36, 0.7 }, { 0.45, 0.3, 0.65 },
	{ 0.75, 0.35, 0.55 }, { 0.55, 0.36, 0.22 }, { 0.82, 0.7, 0.52 }, { 0.95, 0.95, 0.92 },
	{ 0.7, 0.7, 0.7 }, { 0.45, 0.45, 0.47 }, { 0.22, 0.22, 0.24 }, { 0.08, 0.08, 0.09 },
}

local BACKGROUND = { 0, 0, 0, 0.85 }
local TEXT_COLOR = { 0.75, 0.85, 1, 1 }
local CHOSEN_COLOR = { 1, 1, 1, 1 }
local HOVER_COLOR = { 1, 1, 1, 0.5 }

local function inside(r, x, y)
	return x >= r.x and x < r.x + r.width and y >= r.y and y < r.y + r.height
end

-- `sections` laid out top to bottom from (x, y); a section with no colours
-- shows only its label.
function ColourPicker.layout(sections, x, y)
	local width = 2 * PAD + ColourPicker.PER_ROW * SIZE + (ColourPicker.PER_ROW - 1) * GAP
	local layout = { x = x, y = y, width = width, labels = {}, swatches = {} }
	local top = y + PAD
	for _, section in ipairs(sections) do
		layout.labels[#layout.labels + 1] = { text = section.label, x = x + PAD, y = top }
		top = top + LABEL_H
		local rows = math.ceil(#section.colors / ColourPicker.PER_ROW)
		for i, color in ipairs(section.colors) do
			local col, row = (i - 1) % ColourPicker.PER_ROW, math.floor((i - 1) / ColourPicker.PER_ROW)
			layout.swatches[#layout.swatches + 1] = {
				section = section.id,
				color = color,
				x = x + PAD + col * (SIZE + GAP),
				y = top + row * (SIZE + GAP),
				width = SIZE,
				height = SIZE,
			}
		end
		top = top + rows * (SIZE + GAP) + GAP
	end
	layout.height = top - y + PAD - GAP
	return layout
end

-- The swatch under screen point (x, y), or nil.
function ColourPicker.hit(layout, x, y)
	for _, swatch in ipairs(layout and layout.swatches or {}) do
		if inside(swatch, x, y) then
			return swatch
		end
	end
	return nil
end

-- Whether screen point (x, y) is on the picker.
function ColourPicker.contains(layout, x, y)
	return layout ~= nil and inside(layout, x, y)
end

-- Colour `color` (a node colour) as { r, g, b } in `palette`.
local function rgb(color, palette)
	if type(color) == "string" then
		return palette[color]
	end
	return color
end

-- Draws `layout`, team slots in `palette`'s colours. `chosen` maps a
-- section id to the colour to mark in it (or is nil); the swatch under
-- `mouse` ({ x, y } or nil) is outlined.
function ColourPicker.draw(layout, palette, chosen, mouse)
	if not layout then
		return
	end
	chosen = chosen or {}
	love.graphics.push("all")
	love.graphics.setColor(BACKGROUND)
	love.graphics.rectangle("fill", layout.x, layout.y, layout.width, layout.height)
	love.graphics.setColor(TEXT_COLOR)
	for _, label in ipairs(layout.labels) do
		love.graphics.print(label.text, label.x, label.y)
	end
	love.graphics.setLineWidth(2)
	for _, swatch in ipairs(layout.swatches) do
		local c = rgb(swatch.color, palette)
		love.graphics.setColor(c[1], c[2], c[3], 1)
		love.graphics.rectangle("fill", swatch.x, swatch.y, swatch.width, swatch.height, 3, 3)
		local mark = chosen[swatch.section]
		if mark ~= nil and RecentColours.same(mark, swatch.color) then
			love.graphics.setColor(CHOSEN_COLOR)
			love.graphics.rectangle("line", swatch.x - 2, swatch.y - 2, swatch.width + 4, swatch.height + 4, 3, 3)
		elseif mouse and inside(swatch, mouse.x, mouse.y) then
			love.graphics.setColor(HOVER_COLOR)
			love.graphics.rectangle("line", swatch.x - 1, swatch.y - 1, swatch.width + 2, swatch.height + 2, 3, 3)
		end
	end
	love.graphics.pop()
end

-- The sections the script builder's picker shows: the team slots, the
-- presets and the recent picks (`recent`, RecentColours).
function ColourPicker.builderSections(recent)
	return {
		{ id = "slot", label = "Team", colors = Palette.SLOTS },
		{ id = "preset", label = "Colours", colors = ColourPicker.PRESETS },
		{ id = "recent", label = "Recent", colors = recent },
	}
end

return ColourPicker
