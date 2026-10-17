-- Keyboard to intents. The app layer is the only one that reads devices
-- (docs/ARCHITECTURE.md "Layers"); the game only sees ctx.intents.
local Input = {}

-- Fills ctx.intents[1] (player 1's move, harvest, eat and place intent) from
-- WASD, E and F. `target` is the tile {x, y} of a held click, which harvests
-- too; nil otherwise. `place` is a placement request the world screen
-- clicked this step (src/game/buildings/placement.lua), or nil. Call once
-- per fixed step, before Session.advance reads it.
function Input.updateIntents(ctx, target, place)
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
	ctx.intents[1] = { x = x, y = y, harvest = isDown("e") or target ~= nil, eat = isDown("f"), target = target, place = place }
end

return Input
