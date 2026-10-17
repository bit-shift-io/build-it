-- Draws the hover card (text from src/game/components/status.lua) beside
-- the pointer, in screen space.
local Card = {}

local PAD, LINE, OFFSET = 6, 16, 14
local BAR_W, BAR_H = 60, 8
local BAR_COLOURS = { Health = { 0.85, 0.2, 0.2 }, Hunger = { 0.9, 0.65, 0.15 }, Tiredness = { 0.35, 0.5, 0.9 } }

-- lines: the card's text lines; bars: { label, value 0..1 } drawn as filled
-- bars below them (Status.bars), or nil; (x, y): the pointer's screen
-- position.
function Card.draw(lines, x, y, bars)
	bars = bars or {}
	local font = love.graphics.getFont()
	local labelW = 0
	for _, bar in ipairs(bars) do
		labelW = math.max(labelW, font:getWidth(bar.label))
	end
	local width = labelW > 0 and labelW + 6 + BAR_W or 0
	for _, text in ipairs(lines) do
		width = math.max(width, font:getWidth(text))
	end
	local left, top = x + OFFSET, y + OFFSET
	love.graphics.push("all")
	love.graphics.setColor(0, 0, 0, 0.75)
	love.graphics.rectangle("fill", left, top, width + PAD * 2, (#lines + #bars) * LINE + PAD * 2)
	love.graphics.setColor(1, 1, 1, 1)
	for i, text in ipairs(lines) do
		love.graphics.print(text, left + PAD, top + PAD + (i - 1) * LINE)
	end
	for i, bar in ipairs(bars) do
		local rowY = top + PAD + (#lines + i - 1) * LINE
		love.graphics.setColor(1, 1, 1, 1)
		love.graphics.print(bar.label, left + PAD, rowY)
		local barX, barY = left + PAD + labelW + 6, rowY + (LINE - BAR_H) / 2
		love.graphics.setColor(0.2, 0.2, 0.2, 1)
		love.graphics.rectangle("fill", barX, barY, BAR_W, BAR_H)
		love.graphics.setColor(BAR_COLOURS[bar.label])
		love.graphics.rectangle("fill", barX, barY, BAR_W * math.max(0, math.min(1, bar.value)), BAR_H)
	end
	love.graphics.pop()
end

return Card
