-- The title screen shown at launch: Continue (only when the save slot holds
-- a world) and New game. Up/Down (or W/S) move the selection, Return or
-- Space picks it, a click picks the option under the pointer. Picking only
-- sets screen.choice; src/app/flow.lua starts the session.
local Screen = require("src.app.screen")

local TitleScreen = {}

-- Layout, px.
local BUTTON_WIDTH, BUTTON_HEIGHT, GAP = 240, 40, 12

-- hasSave: whether Continue is offered.
function TitleScreen.new(hasSave)
	local options = {}
	if hasSave then
		options[#options + 1] = { id = "continue", label = "Continue" }
	end
	options[#options + 1] = { id = "new", label = "New game" }
	return {
		options = options,
		selected = 1,
		-- The picked option's id ("continue" | "new"), until the flow acts.
		choice = nil,
		-- Why the last pick failed (e.g. an unreadable save), or nil.
		message = nil,
	}
end

function TitleScreen.options(screen)
	return screen.options
end

-- Each option's button: { id, label, x, y, width, height }, centred.
function TitleScreen.buttons(screen)
	local w, h = Screen.dimensions()
	local total = #screen.options * BUTTON_HEIGHT + (#screen.options - 1) * GAP
	local top = (h - total) / 2
	local buttons = {}
	for i, option in ipairs(screen.options) do
		buttons[i] = {
			id = option.id,
			label = option.label,
			x = (w - BUTTON_WIDTH) / 2,
			y = top + (i - 1) * (BUTTON_HEIGHT + GAP),
			width = BUTTON_WIDTH,
			height = BUTTON_HEIGHT,
		}
	end
	return buttons
end

local MOVE = { up = -1, w = -1, down = 1, s = 1 }

function TitleScreen.keypressed(screen, key)
	if MOVE[key] then
		screen.selected = (screen.selected - 1 + MOVE[key]) % #screen.options + 1
	elseif key == "return" or key == "space" then
		screen.choice = screen.options[screen.selected].id
	end
end

function TitleScreen.mousepressed(screen, x, y, button)
	if button ~= 1 then
		return
	end
	for i, b in ipairs(TitleScreen.buttons(screen)) do
		if x >= b.x and x < b.x + b.width and y >= b.y and y < b.y + b.height then
			screen.selected = i
			screen.choice = b.id
		end
	end
end

function TitleScreen.draw(screen)
	local w = Screen.dimensions()
	local font = love.graphics.getFont()
	local buttons = TitleScreen.buttons(screen)
	love.graphics.push("all")
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.printf("Build-it", 0, buttons[1].y - 3 * BUTTON_HEIGHT, w, "center")
	for i, b in ipairs(buttons) do
		if i == screen.selected then
			love.graphics.setColor(0.35, 0.55, 0.8, 1)
		else
			love.graphics.setColor(0.22, 0.24, 0.27, 1)
		end
		love.graphics.rectangle("fill", b.x, b.y, b.width, b.height, 4, 4)
		love.graphics.setColor(1, 1, 1, 1)
		love.graphics.printf(b.label, b.x, b.y + (b.height - font:getHeight()) / 2, b.width, "center")
	end
	if screen.message then
		local last = buttons[#buttons]
		love.graphics.setColor(1, 0.45, 0.4, 1)
		love.graphics.printf(screen.message, 0, last.y + last.height + 2 * GAP, w, "center")
	end
	love.graphics.pop()
end

return TitleScreen
