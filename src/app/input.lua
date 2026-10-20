-- Keyboard to intents. The app layer is the only one that reads devices
-- (docs/ARCHITECTURE.md "Layers"); the game only sees ctx.intents.
local Input = {}

-- The world-space move for screen direction (sx, sy) in `view`: the ground
-- matrix inverted, then normalized so diagonals are no faster. The identity
-- ground (3/4 top-down) leaves the direction as it is.
function Input.toWorld(view, sx, sy)
	if not view then
		return sx, sy
	end
	local a, b, c, d = view.ground[1], view.ground[2], view.ground[3], view.ground[4]
	if a == 1 and b == 0 and c == 0 and d == 1 then
		return sx, sy
	end
	local det = a * d - b * c
	local x, y = (d * sx - b * sy) / det, (a * sy - c * sx) / det
	local length = math.sqrt(x * x + y * y)
	if length == 0 then
		return 0, 0
	end
	return x / length, y / length
end

-- Fills ctx.intents[1] (player 1's move, harvest, eat and place intent) from
-- WASD, E and F. `target` is the tile {x, y} of a held click, which harvests
-- too; nil otherwise. `place` is a placement request the world screen
-- clicked this step (src/game/buildings/placement.lua), or nil. Call once
-- per fixed step, before Session.advance reads it. `blocked` is true while a
-- menu or the picker is open: the keys type into it, so no intent is sent
-- (docs/memory/world-screen-modal-input.md). `view` is the active
-- config.views entry (nil: top-down): WASD move on screen, so the screen
-- direction is turned into world space through the view's ground matrix.
function Input.updateIntents(ctx, target, place, blocked, view)
	if blocked then
		ctx.intents[1] = { x = 0, y = 0, harvest = false, eat = false, place = place }
		return
	end
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
	x, y = Input.toWorld(view, x, y)
	ctx.intents[1] = { x = x, y = y, harvest = isDown("e") or target ~= nil, eat = isDown("f"), target = target, place = place }
end

return Input
