-- The settings screen, opened from the title: pick the view. Up/Down (or
-- W/S) move, Return or Space picks, a click picks the button under the
-- pointer; the current view is marked. Picking only sets screen.choice (a
-- view name); src/app/flow.lua stores it. Esc is handled by the flow.
-- Buttons reuse the title screen's layout.
local Screen = require("src.app.screen")
local TitleScreen = require("src.app.screens.title")
local Settings = require("src.game.settings")

local SettingsScreen = {}

-- current: the view now in effect.
function SettingsScreen.new(config, current)
	local options = {}
	local selected = 1
	for i, name in ipairs(Settings.views(config)) do
		options[i] = { id = name, label = name }
		if name == current then
			selected = i
		end
	end
	return { options = options, selected = selected, current = current, choice = nil }
end

SettingsScreen.buttons = TitleScreen.buttons

function SettingsScreen.keypressed(screen, key)
	TitleScreen.keypressed(screen, key)
end

function SettingsScreen.mousepressed(screen, x, y, button)
	TitleScreen.mousepressed(screen, x, y, button)
end

function SettingsScreen.draw(screen)
	local w = Screen.dimensions()
	local font = love.graphics.getFont()
	local buttons = SettingsScreen.buttons(screen)
	love.graphics.push("all")
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.printf("View (Esc: back)", 0, buttons[1].y - 2 * buttons[1].height, w, "center")
	for i, b in ipairs(buttons) do
		if i == screen.selected then
			love.graphics.setColor(0.35, 0.55, 0.8, 1)
		else
			love.graphics.setColor(0.22, 0.24, 0.27, 1)
		end
		love.graphics.rectangle("fill", b.x, b.y, b.width, b.height, 4, 4)
		love.graphics.setColor(1, 1, 1, 1)
		local label = b.id == screen.current and (b.label .. "  *") or b.label
		love.graphics.printf(label, b.x, b.y + (b.height - font:getHeight()) / 2, b.width, "center")
	end
	love.graphics.pop()
end

return SettingsScreen
