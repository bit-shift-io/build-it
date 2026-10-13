-- Keyboard to intents. The app layer is the only one that reads devices
-- (docs/ARCHITECTURE.md "Layers"); the game only sees ctx.intents.
local Input = {}

-- Fills ctx.intents[1] (player 1's move intent) from WASD. Call once per
-- fixed step, before Session.advance reads it.
function Input.updateIntents(ctx)
	local isDown = love.keyboard.isDown
	local x, y = 0, 0
	if isDown("a") then
		x = x - 1
	end
	if isDown("d") then
		x = x + 1
	end
	if isDown("w") then
		y = y - 1
	end
	if isDown("s") then
		y = y + 1
	end
	ctx.intents[1] = { x = x, y = y }
end

return Input
