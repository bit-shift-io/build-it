-- The flat tile world. A world table is plain data:
--   { width = <tiles>, height = <tiles> }
-- Tile size in pixels comes from config.tileSize, so the world itself holds
-- no tuning numbers. Pure -- no `love.*` (docs/ARCHITECTURE.md "Layers").
local World = {}

-- The world's size in pixels.
function World.pixelSize(world, config)
	return world.width * config.tileSize, world.height * config.tileSize
end

-- The pixel position of the world's centre.
function World.center(world, config)
	local w, h = World.pixelSize(world, config)
	return w / 2, h / 2
end

return World
