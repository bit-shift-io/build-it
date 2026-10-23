-- The settings screen, opened from the title (and as the world's
-- overlay): pick the view and the two team colours. Up/Down (or W/S) move,
-- Return or Space picks, a click picks the view button under the pointer;
-- the current view is marked. Below the buttons, a colour picker
-- (src/app/ui/colour_picker.lua) per team colour, primary and secondary:
-- a click on a swatch makes it that colour. Picking only sets screen.choice
-- (a view name) or screen.colourChoice ({ field, color }); the flow stores
-- them (src/app/flow.lua). Esc is handled by the flow. Buttons reuse the
-- title screen's layout.
local Screen = require("src.app.screen")
local TitleScreen = require("src.app.screens.title")
local Settings = require("src.game.settings")
local Palette = require("src.game.palette")
local ColourPicker = require("src.app.ui.colour_picker")

local SettingsScreen = {}

-- The gap between the last view button and the colour picker, px.
local PICKER_GAP = 24

-- current: the view now in effect. colours: the team colours now in effect,
-- { primary, secondary } (each { r, g, b }; default Palette's).
function SettingsScreen.new(config, current, colours)
	colours = colours or { primary = Palette.DEFAULT_PRIMARY, secondary = Palette.DEFAULT_SECONDARY }
	local options = {}
	local selected = 1
	for i, name in ipairs(Settings.views(config)) do
		options[i] = { id = name, label = name }
		if name == current then
			selected = i
		end
	end
	return {
		options = options,
		selected = selected,
		current = current,
		choice = nil,
		-- The team colours shown as chosen, and the last colour picked
		-- ({ field = "primary" | "secondary", color }) until the flow stores it.
		colours = { primary = colours.primary, secondary = colours.secondary },
		colourChoice = nil,
	}
end

SettingsScreen.buttons = TitleScreen.buttons

-- The team colour pickers' layout (ColourPicker.layout): a section per
-- field, centred under the view buttons.
function SettingsScreen.colourPicker(screen)
	local buttons = SettingsScreen.buttons(screen)
	local last = buttons[#buttons]
	local sections = {
		{ id = "primary", label = "Primary colour", colors = ColourPicker.PRESETS },
		{ id = "secondary", label = "Secondary colour", colors = ColourPicker.PRESETS },
	}
	local probe = ColourPicker.layout(sections, 0, 0)
	return ColourPicker.layout(sections, last.x + (last.width - probe.width) / 2, last.y + last.height + PICKER_GAP)
end

function SettingsScreen.keypressed(screen, key)
	TitleScreen.keypressed(screen, key)
end

function SettingsScreen.mousepressed(screen, x, y, button)
	local swatch = button == 1 and ColourPicker.hit(SettingsScreen.colourPicker(screen), x, y)
	if swatch then
		local c = swatch.color
		screen.colours[swatch.section] = c
		screen.colourChoice = { field = swatch.section, color = { c[1], c[2], c[3] } }
		return
	end
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
	local c = screen.colours
	ColourPicker.draw(SettingsScreen.colourPicker(screen), Palette.derive(c.primary, c.secondary), c, nil)
	love.graphics.pop()
end

return SettingsScreen
