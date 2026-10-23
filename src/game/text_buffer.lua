-- The code panel's text (docs/CONTEXT.md "Locked script": edited through
-- params and the code panel): lines of text, a cursor and an optional
-- selection, and the editing operations on them. Pure; plain LuaJIT.
--
-- A position is { line, col }: line from 1, col the byte offset into the
-- line (0 before its first character). The selection runs from the anchor
-- to the cursor, either way round; there is none when anchor is nil.
local TextBuffer = {}

-- A buffer holding `text`, the cursor at its start.
function TextBuffer.new(text)
	local lines = {}
	for line in ((text or ""):gsub("\r\n?", "\n") .. "\n"):gmatch("([^\n]*)\n") do
		lines[#lines + 1] = line
	end
	return { lines = lines, line = 1, col = 0, anchor = nil }
end

-- The buffer's text, its lines joined by "\n".
function TextBuffer.text(buf)
	return table.concat(buf.lines, "\n")
end

-- `line`, `col` held inside the buffer.
local function clamp(buf, line, col)
	line = math.max(1, math.min(#buf.lines, line))
	return line, math.max(0, math.min(#buf.lines[line], col))
end

-- Moves the cursor to (line, col), held inside the text. With `extend` the
-- selection grows from where the cursor was; else there is none.
function TextBuffer.place(buf, line, col, extend)
	if extend then
		buf.anchor = buf.anchor or { buf.line, buf.col }
	else
		buf.anchor = nil
	end
	buf.line, buf.col = clamp(buf, line, col)
end

-- Where the character before byte `col` of `s` starts (UTF-8 aware).
local function previous(s, col)
	col = col - 1
	while col > 0 and s:byte(col + 1) >= 128 and s:byte(col + 1) < 192 do
		col = col - 1
	end
	return col
end

-- Where the character from byte `col` of `s` ends (UTF-8 aware).
local function following(s, col)
	col = col + 1
	while col < #s and s:byte(col + 1) >= 128 and s:byte(col + 1) < 192 do
		col = col + 1
	end
	return col
end

-- Removes the text from (l1, c1) to (l2, c2), the first before the second,
-- the cursor where it began, nothing selected.
local function remove(buf, l1, c1, l2, c2)
	buf.lines[l1] = buf.lines[l1]:sub(1, c1) .. buf.lines[l2]:sub(c2 + 1)
	for _ = l1 + 1, l2 do
		table.remove(buf.lines, l1 + 1)
	end
	buf.line, buf.col, buf.anchor = l1, c1, nil
end

-- The position before the other in each pair of a, b.
local function ordered(l1, c1, l2, c2)
	if l2 < l1 or (l2 == l1 and c2 < c1) then
		return l2, c2, l1, c1
	end
	return l1, c1, l2, c2
end

-- The selection's start and end (line, col, line, col), or nil when there
-- is none or it is empty.
local function range(buf)
	local a = buf.anchor
	if not a or (a[1] == buf.line and a[2] == buf.col) then
		return nil
	end
	return ordered(a[1], a[2], buf.line, buf.col)
end

-- Removes the selection; false when there was none.
local function removeSelection(buf)
	local l1, c1, l2, c2 = range(buf)
	buf.anchor = nil
	if not l1 then
		return false
	end
	remove(buf, l1, c1, l2, c2)
	return true
end

-- Puts `text` at the cursor, in place of the selection, the cursor after
-- it.
function TextBuffer.insert(buf, text)
	removeSelection(buf)
	local before = buf.lines[buf.line]:sub(1, buf.col)
	local after = buf.lines[buf.line]:sub(buf.col + 1)
	local added = TextBuffer.new(text).lines
	local last = #added
	local line = buf.line
	buf.col = #added[last]
	added[1] = before .. added[1]
	added[last] = added[last] .. after
	if last == 1 then
		buf.col = buf.col + #before
	end
	buf.lines[line] = added[1]
	for i = 2, last do
		table.insert(buf.lines, line + i - 1, added[i])
	end
	buf.line = line + last - 1
end

-- The selected text, or nil when nothing is selected.
function TextBuffer.selected(buf)
	local l1, c1, l2, c2 = range(buf)
	if not l1 then
		return nil
	end
	if l1 == l2 then
		return buf.lines[l1]:sub(c1 + 1, c2)
	end
	local out = { buf.lines[l1]:sub(c1 + 1) }
	for i = l1 + 1, l2 - 1 do
		out[#out + 1] = buf.lines[i]
	end
	out[#out + 1] = buf.lines[l2]:sub(1, c2)
	return table.concat(out, "\n")
end

-- Removes the selection and returns its text, or nil when nothing is
-- selected.
function TextBuffer.cut(buf)
	local text = TextBuffer.selected(buf)
	removeSelection(buf)
	return text
end

-- Selects the whole text, the cursor at its end.
function TextBuffer.selectAll(buf)
	buf.anchor = { 1, 0 }
	buf.line = #buf.lines
	buf.col = #buf.lines[buf.line]
end

-- Display cells a tab steps to a multiple of.
TextBuffer.TAB = 4

-- The display cell (from 0) byte `col` of line `s` is drawn at: a UTF-8
-- character takes one cell, a tab steps to the next multiple of TAB.
function TextBuffer.cell(s, col)
	local cell, i = 0, 0
	while i < col and i < #s do
		if s:byte(i + 1) == 9 then
			cell = cell + TextBuffer.TAB - cell % TextBuffer.TAB
		else
			cell = cell + 1
		end
		i = following(s, i)
	end
	return cell
end

-- The byte col of line `s` nearest display cell `cell`.
function TextBuffer.colAt(s, cell)
	local i, at = 0, 0
	while i < #s do
		local nextAt = TextBuffer.cell(s, following(s, i))
		if cell < (at + nextAt) / 2 then
			return i
		end
		i, at = following(s, i), nextAt
	end
	return #s
end

-- Moves the cursor `how`: "left" or "right" a character (across line
-- ends), "up" or "down" a line in the same display column, "home" or
-- "end" of the line. With `extend` the selection grows; else there is
-- none.
function TextBuffer.move(buf, how, extend)
	local line, col = buf.line, buf.col
	local s = buf.lines[line]
	if how == "left" then
		if col > 0 then
			col = previous(s, col)
		elseif line > 1 then
			line = line - 1
			col = #buf.lines[line]
		end
	elseif how == "right" then
		if col < #s then
			col = following(s, col)
		elseif line < #buf.lines then
			line, col = line + 1, 0
		end
	elseif how == "up" or how == "down" then
		local target = math.max(1, math.min(#buf.lines, line + (how == "up" and -1 or 1)))
		if target ~= line then
			col = TextBuffer.colAt(buf.lines[target], TextBuffer.cell(s, col))
			line = target
		end
	elseif how == "home" then
		col = 0
	elseif how == "end" then
		col = #s
	end
	TextBuffer.place(buf, line, col, extend)
end

-- Removes the selection, else the character before the cursor (or the
-- line break, joining the line to the one above).
function TextBuffer.backspace(buf)
	if removeSelection(buf) then
		return
	end
	if buf.col > 0 then
		remove(buf, buf.line, previous(buf.lines[buf.line], buf.col), buf.line, buf.col)
	elseif buf.line > 1 then
		remove(buf, buf.line - 1, #buf.lines[buf.line - 1], buf.line, 0)
	end
end

-- Removes the selection, else the character after the cursor (or the line
-- break, joining the next line on).
function TextBuffer.delete(buf)
	if removeSelection(buf) then
		return
	end
	local s = buf.lines[buf.line]
	if buf.col < #s then
		remove(buf, buf.line, buf.col, buf.line, following(s, buf.col))
	elseif buf.line < #buf.lines then
		remove(buf, buf.line, buf.col, buf.line + 1, 0)
	end
end

return TextBuffer
