-- The script builder's code panel (docs/CONTEXT.md "Locked script": edited
-- through params and the code panel): the open design script as text down
-- the right of the view, line numbers in a gutter, a header with Run and
-- Open folder and the save folder's path, a footer with the last error.
-- Text sits on a fixed character grid, so any font draws it monospaced.
-- Layout is pure arithmetic (testable); only draw touches love.graphics.
local TextBuffer = require("src.game.text_buffer")

local CodePanel = {}

-- One text row's height and one character cell's width, in px.
CodePanel.LINE_HEIGHT = 15
CodePanel.CHAR_WIDTH = 7

-- The share of the view's width the panel takes, from the right edge.
local SHARE = 0.5
-- The header: a row of buttons over a row for the folder path.
local HEADER = 46
local BUTTON_H = 20
local FOOTER = 34
local PAD = 6
local BUTTON_W = { run = 112, folder = 92 }

local BACKGROUND = { 0.08, 0.09, 0.11, 0.96 }
local GUTTER_COLOR = { 0.12, 0.13, 0.16, 1 }
local NUMBER_COLOR = { 0.45, 0.47, 0.52, 1 }
local TEXT_COLOR = { 0.9, 0.9, 0.88, 1 }
local SELECTION_COLOR = { 0.25, 0.38, 0.62, 1 }
local ERROR_BAND = { 0.45, 0.12, 0.12, 1 }
local ERROR_TEXT = { 1, 0.5, 0.45, 1 }
local BUTTON_COLOR = { 0.24, 0.26, 0.3, 1 }
local PATH_COLOR = { 0.65, 0.67, 0.7, 1 }
local CURSOR_COLOR = { 1, 1, 1, 1 }

-- The panel over the right part of `view` ({ x, y, width, height }) for a
-- text of `lines` lines: { x, y, width, height, run, folder (buttons
-- { x, y, width, height }), text ({ x, y, width, height }: where lines
-- draw, right of the gutter), gutter (its x), rows (lines that fit) }.
function CodePanel.layout(view, lines)
	local width = math.floor(view.width * SHARE)
	local x, y = view.x + view.width - width, view.y
	local gutter = (#tostring(math.max(lines, 1)) + 2) * CodePanel.CHAR_WIDTH
	local textY = y + HEADER
	local textH = view.height - HEADER - FOOTER
	local by = y + 4
	local run = { x = x + PAD, y = by, width = BUTTON_W.run, height = BUTTON_H }
	local folder = { x = run.x + run.width + PAD, y = by, width = BUTTON_W.folder, height = BUTTON_H }
	return {
		x = x,
		y = y,
		width = width,
		height = view.height,
		run = run,
		folder = folder,
		gutter = x,
		text = { x = x + gutter + PAD, y = textY, width = width - gutter - 2 * PAD, height = textH },
		rows = math.max(1, math.floor(textH / CodePanel.LINE_HEIGHT)),
	}
end

local function inside(r, x, y)
	return r ~= nil and x >= r.x and x < r.x + r.width and y >= r.y and y < r.y + r.height
end

-- Whether screen point (x, y) is on the panel.
function CodePanel.contains(layout, x, y)
	return inside(layout, x, y)
end

-- What is under screen point (x, y): "run", "folder", "text", or nil.
function CodePanel.hit(layout, x, y)
	if not layout then
		return nil
	end
	if inside(layout.run, x, y) then
		return "run"
	elseif inside(layout.folder, x, y) then
		return "folder"
	elseif inside(layout.text, x, y) then
		return "text"
	end
	return nil
end

-- The buffer position (line, col) under screen point (x, y) with the text
-- scrolled `scroll` lines down; held inside the text.
function CodePanel.position(layout, buffer, scroll, x, y)
	local line = scroll + 1 + math.floor((y - layout.text.y) / CodePanel.LINE_HEIGHT)
	line = math.max(1, math.min(#buffer.lines, line))
	local cell = (x - layout.text.x) / CodePanel.CHAR_WIDTH
	return line, TextBuffer.colAt(buffer.lines[line], cell)
end

-- `scroll` moved by `by` lines (or, without, just enough to show the
-- cursor's line), held to the text.
function CodePanel.scroll(layout, buffer, scroll, by)
	if by then
		scroll = scroll + by
	elseif buffer.line <= scroll then
		scroll = buffer.line - 1
	elseif buffer.line > scroll + layout.rows then
		scroll = buffer.line - layout.rows
	end
	return math.max(0, math.min(math.max(0, #buffer.lines - layout.rows), scroll))
end

-- The selection's start and end positions in order, or nil.
local function selection(buffer)
	local a = buffer.anchor
	if not a then
		return nil
	end
	local l1, c1, l2, c2 = a[1], a[2], buffer.line, buffer.col
	if l2 < l1 or (l2 == l1 and c2 < c1) then
		l1, c1, l2, c2 = l2, c2, l1, c1
	end
	return l1, c1, l2, c2
end

local function button(r, label)
	love.graphics.setColor(BUTTON_COLOR)
	love.graphics.rectangle("fill", r.x, r.y, r.width, r.height, 3, 3)
	love.graphics.setColor(TEXT_COLOR)
	love.graphics.print(label, r.x + 6, r.y + 3)
end

-- Draws the panel: `buffer` scrolled `scroll` lines, line `errorLine` (or
-- nil) marked, `folder` (the save folder's path) in the header and
-- `message` (or nil) in the footer.
function CodePanel.draw(layout, buffer, scroll, errorLine, folder, message)
	local L, C = CodePanel.LINE_HEIGHT, CodePanel.CHAR_WIDTH
	local t = layout.text
	love.graphics.push("all")
	love.graphics.setColor(BACKGROUND)
	love.graphics.rectangle("fill", layout.x, layout.y, layout.width, layout.height)
	button(layout.run, "Run (Ctrl+Enter)")
	button(layout.folder, "Open folder")
	love.graphics.setColor(PATH_COLOR)
	love.graphics.print("Saved in " .. folder, layout.x + PAD, layout.run.y + BUTTON_H + 4)
	love.graphics.setColor(GUTTER_COLOR)
	love.graphics.rectangle("fill", layout.gutter, t.y, t.x - PAD - layout.gutter, t.height)
	love.graphics.setScissor(layout.x, t.y, layout.width, t.height)
	local l1, c1, l2, c2 = selection(buffer)
	for row = 1, layout.rows do
		local i = scroll + row
		local s = buffer.lines[i]
		if not s then
			break
		end
		local y = t.y + (row - 1) * L
		if i == errorLine then
			love.graphics.setColor(ERROR_BAND)
			love.graphics.rectangle("fill", t.x - PAD, y, t.width + PAD, L)
		end
		if l1 and i >= l1 and i <= l2 then
			local from = i == l1 and TextBuffer.cell(s, c1) or 0
			local to = i == l2 and TextBuffer.cell(s, c2) or TextBuffer.cell(s, #s) + 1
			love.graphics.setColor(SELECTION_COLOR)
			love.graphics.rectangle("fill", t.x + from * C, y, (to - from) * C, L)
		end
		love.graphics.setColor(i == errorLine and ERROR_TEXT or NUMBER_COLOR)
		love.graphics.printf(tostring(i), layout.gutter, y, t.x - PAD - layout.gutter - C, "right")
		love.graphics.setColor(TEXT_COLOR)
		local col = 0
		while col < #s do
			local stop = col + 1
			while stop < #s and s:byte(stop + 1) >= 128 and s:byte(stop + 1) < 192 do
				stop = stop + 1
			end
			local char = s:sub(col + 1, stop)
			if char ~= "\t" and char ~= " " then
				love.graphics.print(char, t.x + TextBuffer.cell(s, col) * C, y)
			end
			col = stop
		end
		if i == buffer.line then
			love.graphics.setColor(CURSOR_COLOR)
			local cx = t.x + TextBuffer.cell(s, buffer.col) * C
			love.graphics.rectangle("fill", cx, y + 1, 1, L - 2)
		end
	end
	love.graphics.setScissor()
	if message then
		love.graphics.setColor(ERROR_TEXT)
		love.graphics.printf(message, layout.x + PAD, layout.y + layout.height - FOOTER + 2, layout.width - 2 * PAD)
	end
	love.graphics.pop()
end

return CodePanel
