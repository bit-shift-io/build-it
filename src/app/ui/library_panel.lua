-- The library manager (docs/CONTEXT.md "Design library"): the script
-- builder's panel under top bar slot 7, a Designs tab and a Prefabs tab,
-- New on the Designs tab, and a row per script: a thumbnail, its name and
-- the buttons Open, Duplicate, Rename and Delete -- Reset for a built-in.
-- A Delete armed by its first click reads Confirm. Layout and what a click
-- hits are pure arithmetic; only draw touches love.graphics.
--
--   layout = { x, y, width, height, tab,
--              tabs = { { tab, label, x, y, width, height } },
--              new = { x, y, width, height } or nil,
--              rows = { { entry, blueprint, x, y, width, height,
--                         thumb = { x, y, width, height },
--                         buttons = { { action, label, x, y, width, height } } } } }
local LibraryPanel = {}

local PAD, GAP = 6, 4
local TAB_W, TAB_H = 90, 22
local ROW_H, THUMB = 44, 40
local NAME_W = 150
local BUTTON_H = 22
-- A label character's width, in px, roughly the default font's.
local CHAR_WIDTH = 7

local TABS = { { tab = "designs", label = "Designs" }, { tab = "prefabs", label = "Prefabs" } }

local BACKGROUND = { 0, 0, 0, 0.85 }
local TAB_COLOR = { 0.24, 0.26, 0.3, 1 }
local ACTIVE_COLOR = { 0.3, 0.5, 0.85, 1 }
local BUTTON_COLOR = { 0.2, 0.22, 0.26, 1 }
local ARMED_COLOR = { 0.75, 0.22, 0.18, 1 }
local HOVER_COLOR = { 1, 1, 1, 0.15 }
local TEXT_COLOR = { 0.92, 0.92, 0.92, 1 }
local DIM_COLOR = { 0.6, 0.65, 0.75, 1 }

local function inside(r, x, y)
	return x >= r.x and x < r.x + r.width and y >= r.y and y < r.y + r.height
end

local function buttonWidth(label)
	return (#label + 2) * CHAR_WIDTH
end

-- The buttons of a row for `entry` ({ name, builtin }).
local function actions(entry)
	return {
		{ action = "open", label = "Open" },
		{ action = "duplicate", label = "Duplicate" },
		{ action = "rename", label = "Rename" },
		entry.builtin and { action = "reset", label = "Reset" } or { action = "delete", label = "Delete" },
	}
end

-- The panel at (x, y) showing tab `tab` ("designs" | "prefabs") with rows
-- `entries` ({ { name, builtin, blueprint }, ... }; blueprint, for the
-- thumbnail, is nil when the script doesn't compile).
function LibraryPanel.layout(entries, tab, x, y)
	local buttonsW = 0
	for _, b in ipairs(actions({})) do
		buttonsW = buttonsW + buttonWidth(b.label) + GAP
	end
	local width = 2 * PAD + THUMB + GAP + NAME_W + buttonsW
	local layout = { x = x, y = y, width = width, tab = tab, tabs = {}, rows = {} }
	local tx = x + PAD
	for i, t in ipairs(TABS) do
		layout.tabs[i] = { tab = t.tab, label = t.label, x = tx, y = y + PAD, width = TAB_W, height = TAB_H }
		tx = tx + TAB_W + GAP
	end
	if tab == "designs" then
		local w = buttonWidth("New")
		layout.new = { x = x + width - PAD - w, y = y + PAD, width = w, height = TAB_H }
	end
	local top = y + PAD + TAB_H + GAP
	for i, entry in ipairs(entries) do
		local row = {
			entry = entry,
			blueprint = entry.blueprint,
			x = x + PAD,
			y = top,
			width = width - 2 * PAD,
			height = ROW_H,
			thumb = { x = x + PAD, y = top + (ROW_H - THUMB) / 2, width = THUMB, height = THUMB },
			buttons = {},
		}
		local bx = x + PAD + THUMB + GAP + NAME_W
		for j, b in ipairs(actions(entry)) do
			local w = buttonWidth(b.label)
			row.buttons[j] = { action = b.action, label = b.label, x = bx, y = top + (ROW_H - BUTTON_H) / 2, width = w, height = BUTTON_H }
			bx = bx + w + GAP
		end
		layout.rows[i] = row
		top = top + ROW_H
	end
	layout.height = top - y + PAD
	return layout
end

-- What screen point (x, y) hits: { tab = <tab> }, { new = true }, or
-- { row, action } for a row's button; nil for anything else.
function LibraryPanel.hit(layout, x, y)
	if not layout then
		return nil
	end
	for _, t in ipairs(layout.tabs) do
		if inside(t, x, y) then
			return { tab = t.tab }
		end
	end
	if layout.new and inside(layout.new, x, y) then
		return { new = true }
	end
	for _, row in ipairs(layout.rows) do
		for _, b in ipairs(row.buttons) do
			if inside(b, x, y) then
				return { row = row, action = b.action }
			end
		end
	end
	return nil
end

-- Whether screen point (x, y) is on the panel.
function LibraryPanel.contains(layout, x, y)
	return layout ~= nil and inside(layout, x, y)
end

-- Draws `layout`. `armed` is the name whose Delete awaits its confirming
-- click, or nil; `open` the name of the script the builder has open on
-- this tab, or nil; the box under `mouse` ({ x, y } or nil) is lit.
-- `thumbnail(blueprint, rect)` draws a row's thumbnail.
function LibraryPanel.draw(layout, armed, open, mouse, thumbnail)
	if not layout then
		return
	end
	love.graphics.push("all")
	love.graphics.setColor(BACKGROUND)
	love.graphics.rectangle("fill", layout.x, layout.y, layout.width, layout.height)
	local function box(r, color, label)
		love.graphics.setColor(color)
		love.graphics.rectangle("fill", r.x, r.y, r.width, r.height, 3, 3)
		if mouse and inside(r, mouse.x, mouse.y) then
			love.graphics.setColor(HOVER_COLOR)
			love.graphics.rectangle("fill", r.x, r.y, r.width, r.height, 3, 3)
		end
		love.graphics.setColor(TEXT_COLOR)
		love.graphics.print(label, r.x + CHAR_WIDTH, r.y + 4)
	end
	for _, t in ipairs(layout.tabs) do
		box(t, t.tab == layout.tab and ACTIVE_COLOR or TAB_COLOR, t.label)
	end
	if layout.new then
		box(layout.new, TAB_COLOR, "New")
	end
	for _, row in ipairs(layout.rows) do
		if row.blueprint then
			thumbnail(row.blueprint, row.thumb)
		end
		local name = row.entry.name
		love.graphics.setColor(name == open and ACTIVE_COLOR or TEXT_COLOR)
		love.graphics.print(name, row.thumb.x + THUMB + GAP, row.y + 6)
		if row.entry.builtin then
			love.graphics.setColor(DIM_COLOR)
			love.graphics.print("built-in", row.thumb.x + THUMB + GAP, row.y + 22)
		end
		for _, b in ipairs(row.buttons) do
			local confirm = b.action == "delete" and armed == name
			box(b, confirm and ARMED_COLOR or BUTTON_COLOR, confirm and "Confirm" or b.label)
		end
	end
	love.graphics.pop()
end

return LibraryPanel
