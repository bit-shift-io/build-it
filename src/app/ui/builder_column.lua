-- The script builder's column (docs/CONTEXT.md "Builder column"): named
-- sections (Tree, Actions) stacked down the left under the top bar, each a
-- header row with a collapse toggle over its content. Content taller than the
-- window scrolls. Layout is pure arithmetic (testable); only draw touches
-- love.graphics.
local BuilderColumn = {}

local MARGIN, WIDTH, HEADER_H, GAP = 8, 220, 22, 4
local BAR_GAP, BAR_W, MIN_THUMB = 3, 6, 20

BuilderColumn.WIDTH = WIDTH
BuilderColumn.MARGIN = MARGIN

local HEADER_COLOR = { 0.18, 0.2, 0.25, 0.9 }
local BAR_COLOR = { 1, 1, 1, 0.12 }
local THUMB_COLOR = { 1, 1, 1, 0.45 }

local function inside(r, x, y)
	return x >= r.x and x < r.x + r.width and y >= r.y and y < r.y + r.height
end

local function maxScrollOf(total, height)
	return math.max(0, total - height)
end

local function clamp(scroll, max)
	return math.max(0, math.min(max, scroll))
end

-- Total px the stacked sections take: `sections` are { name, title,
-- height?, collapsed? }; a nil height hides the section, a collapsed one is
-- its header alone.
local function totalHeight(sections)
	local total = MARGIN
	for _, s in ipairs(sections) do
		if s.height then
			total = total + HEADER_H + (s.collapsed and 0 or s.height) + GAP
		end
	end
	return total
end

-- `scroll` held within 0..col.maxScroll of layout `col`.
function BuilderColumn.clampScroll(col, scroll)
	return clamp(scroll, col.maxScroll)
end

-- The column under a top bar `top` px tall, `height` px visible, scrolled
-- `scroll` px: { x, y, width, height, scroll, maxScroll, sections = { {
-- name, title, collapsed, header, content? } }, bar? = { track, thumb } }.
-- Content rects are positioned at the scroll; they may lie outside the
-- visible area. The scroll is clamped.
function BuilderColumn.layout(sections, top, height, scroll)
	local total = totalHeight(sections)
	local max = maxScrollOf(total, height)
	scroll = clamp(scroll or 0, max)
	local out = {
		x = MARGIN, y = top, width = WIDTH, height = height,
		scroll = scroll, maxScroll = max, sections = {},
	}
	local y = top + MARGIN - scroll
	for _, s in ipairs(sections) do
		if s.height then
			local placed = {
				name = s.name,
				title = s.title,
				collapsed = s.collapsed and true or false,
				header = { x = MARGIN, y = y, width = WIDTH, height = HEADER_H },
			}
			y = y + HEADER_H
			if not s.collapsed then
				placed.content = { x = MARGIN, y = y, width = WIDTH, height = s.height }
				y = y + s.height
			end
			y = y + GAP
			out.sections[#out.sections + 1] = placed
		end
	end
	if max > 0 then
		local thumbH = math.max(MIN_THUMB, math.floor(height * height / total))
		thumbH = math.min(thumbH, height)
		local x = MARGIN + WIDTH + BAR_GAP
		out.bar = {
			track = { x = x, y = top, width = BAR_W, height = height },
			thumb = {
				x = x,
				y = top + (height - thumbH) * scroll / max,
				width = BAR_W,
				height = thumbH,
			},
		}
	end
	return out
end

-- The scroll that puts the thumb's grabbed point (`grab` px below its top)
-- under screen y `y`.
function BuilderColumn.dragScroll(col, grab, y)
	local bar = col.bar
	if not bar then
		return 0
	end
	local room = bar.track.height - bar.thumb.height
	if room <= 0 then
		return 0
	end
	local ratio = (y - grab - bar.track.y) / room
	return clamp(ratio * col.maxScroll, col.maxScroll)
end

-- What is at screen point (x, y): { part = "thumb" | "track" } on the bar,
-- { part = "header", name } or { part = "content", name } on a section
-- within the visible area, else nil.
function BuilderColumn.hit(col, x, y)
	if col.bar then
		if inside(col.bar.thumb, x, y) then
			return { part = "thumb" }
		end
		if inside(col.bar.track, x, y) then
			return { part = "track" }
		end
	end
	if not inside(col, x, y) then
		return nil
	end
	for _, s in ipairs(col.sections) do
		if inside(s.header, x, y) then
			return { part = "header", name = s.name }
		end
		if s.content and inside(s.content, x, y) then
			return { part = "content", name = s.name }
		end
	end
	return nil
end

-- Whether (x, y) is on the column: a header, content or the scroll bar, so
-- the click never reaches the model.
function BuilderColumn.contains(col, x, y)
	return BuilderColumn.hit(col, x, y) ~= nil
end

-- Draws the section frames and the scroll bar, clipped to the column.
-- `drawContent(name, content)` draws each open section's own content.
function BuilderColumn.draw(col, drawContent)
	love.graphics.push("all")
	love.graphics.setScissor(col.x, col.y, col.width + BAR_GAP + BAR_W, col.height)
	for _, s in ipairs(col.sections) do
		local h = s.header
		love.graphics.setColor(HEADER_COLOR)
		love.graphics.rectangle("fill", h.x, h.y, h.width, h.height, 4, 4)
		love.graphics.setColor(1, 1, 1, 1)
		love.graphics.print((s.collapsed and "▸ " or "▾ ") .. s.title, h.x + 6, h.y + 4)
		if s.content then
			drawContent(s.name, s.content)
		end
	end
	if col.bar then
		love.graphics.setColor(BAR_COLOR)
		local t = col.bar.track
		love.graphics.rectangle("fill", t.x, t.y, t.width, t.height, 3, 3)
		love.graphics.setColor(THUMB_COLOR)
		local th = col.bar.thumb
		love.graphics.rectangle("fill", th.x, th.y, th.width, th.height, 3, 3)
	end
	love.graphics.setScissor()
	love.graphics.pop()
end

return BuilderColumn
