-- Draws the world's context menu and the building picker, and answers where
-- a click landed. Geometry is pure arithmetic (testable); only draw* touch
-- love.graphics. State lives in src/app/picker.lua and the world screen.
local Picker = require("src.app.picker")
local StorageFacility = require("src.game.components.storage_facility")
local BuildingsRender = require("src.app.render.buildings")

local PickerRender = {}

local MENU_W, ROW_H, PAD = 110, 22, 6
local PICKER_W, HEADER_H = 360, 30
local PICKER_ROW_H, THUMB = 44, 38
local WHITE, RED = { 1, 1, 1, 1 }, { 1, 0.45, 0.4, 1 }

-- The context menu's single entry "Build" opened at (x, y): its rectangle.
function PickerRender.menuItem(menu)
	return { x = menu.x, y = menu.y, w = MENU_W, h = ROW_H }
end

local function inside(rect, x, y)
	return x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h
end

-- Whether screen point (x, y) is on the menu's "Build" entry.
function PickerRender.menuHit(menu, x, y)
	return inside(PickerRender.menuItem(menu), x, y)
end

-- The picker panel's rectangle, centred in a screen of w x h.
function PickerRender.panel(w, h)
	local height = HEADER_H + Picker.ROWS * PICKER_ROW_H + PAD
	return { x = (w - PICKER_W) / 2, y = (h - height) / 2, w = PICKER_W, h = height }
end

-- The rectangle of visible row i (1..Picker.ROWS).
function PickerRender.row(w, h, i)
	local panel = PickerRender.panel(w, h)
	return { x = panel.x + PAD, y = panel.y + HEADER_H + (i - 1) * PICKER_ROW_H, w = panel.w - PAD * 2, h = PICKER_ROW_H }
end

-- The design under screen point (x, y), or nil.
function PickerRender.designAt(picker, w, h, x, y)
	for i, design in ipairs(Picker.visible(picker)) do
		if inside(PickerRender.row(w, h, i), x, y) then
			return design
		end
	end
	return nil
end

-- A cost as sorted { text = "10 plank", short = bool } parts; short when
-- `totals` can't cover that item.
function PickerRender.costParts(cost, totals)
	local short = StorageFacility.short(cost, totals)
	local items = {}
	for item in pairs(cost) do
		table.insert(items, item)
	end
	table.sort(items)
	local parts = {}
	for _, item in ipairs(items) do
		table.insert(parts, { text = cost[item] .. " " .. item, short = short[item] or false })
	end
	return parts
end

-- One picker row for `design` (Library.placeable's { name, blueprint }):
-- its blueprint's sprite (facing N, fixed bake scale 1) fitted into a
-- square, the name, and the cost with short items in red.
-- ctx: { config, totals }.
local function drawRow(design, rect, hover, ctx)
	if hover then
		love.graphics.setColor(1, 1, 1, 0.15)
		love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
	end
	local sprite = BuildingsRender.sprite(ctx.config, design.blueprint, "N", 1)
	local iw, ih = sprite.image:getDimensions()
	local scale = math.min(THUMB / iw, THUMB / ih)
	local tx = rect.x + PAD + (THUMB - iw * scale) / 2
	local ty = rect.y + (rect.h - ih * scale) / 2
	-- Premultiplied, like every baked sprite.
	love.graphics.setBlendMode("alpha", "premultiplied")
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.draw(sprite.image, tx, ty, 0, scale, scale)
	love.graphics.setBlendMode("alpha")

	local textX = rect.x + PAD * 2 + THUMB
	love.graphics.setColor(WHITE)
	love.graphics.print(design.name, textX, rect.y + 5)
	local text = {}
	for _, part in ipairs(PickerRender.costParts(design.blueprint.cost, ctx.totals)) do
		table.insert(text, part.short and RED or WHITE)
		table.insert(text, part.text .. "  ")
	end
	love.graphics.print(text, textX, rect.y + 5 + 18)
end

function PickerRender.drawMenu(menu, mouse)
	local item = PickerRender.menuItem(menu)
	love.graphics.push("all")
	love.graphics.setColor(0, 0, 0, 0.85)
	love.graphics.rectangle("fill", item.x, item.y, item.w, item.h)
	if mouse and inside(item, mouse.x, mouse.y) then
		love.graphics.setColor(1, 1, 1, 0.15)
		love.graphics.rectangle("fill", item.x, item.y, item.w, item.h)
	end
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.print("1 Build", item.x + PAD, item.y + 4)
	love.graphics.pop()
end

-- ctx: { config, totals } for the rows' thumbnails and costs.
function PickerRender.drawPicker(picker, mouse, ctx)
	local w, h = love.graphics.getDimensions()
	local panel = PickerRender.panel(w, h)
	love.graphics.push("all")
	love.graphics.setColor(0, 0, 0, 0.85)
	love.graphics.rectangle("fill", panel.x, panel.y, panel.w, panel.h)
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.print("Search: " .. picker.query .. "_", panel.x + PAD, panel.y + 8)
	local hovered = mouse and PickerRender.designAt(picker, w, h, mouse.x, mouse.y)
	for i, design in ipairs(Picker.visible(picker)) do
		drawRow(design, PickerRender.row(w, h, i), design == hovered, ctx)
	end
	love.graphics.pop()
end

return PickerRender
