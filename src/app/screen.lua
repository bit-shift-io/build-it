-- The window the world is drawn into. The view fills the whole window at
-- any size; the camera centres on it.
local Screen = {}

Screen.BACKGROUND = { 0.08, 0.09, 0.1, 1 }

function Screen.dimensions()
	return love.graphics.getDimensions()
end

return Screen
