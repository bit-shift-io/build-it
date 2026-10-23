-- Starter prefab: a window frame, four bars round an opening in a wall
-- running east. Origin at its north-west ground corner; lengths in tiles,
-- x east, y south, z up. Parametric: opening width and height, bar size.
local width = UI.number({ label = "Width", default = 0.75, min = 0.25, max = 4, step = 0.125 })
local height = UI.number({ label = "Height", default = 0.75, min = 0.25, max = 4, step = 0.125 })
local bar = UI.number({ label = "Bar", default = 0.0625, min = 0.03125, max = 0.25, step = 0.03125 })
local depth = UI.number({ label = "Depth", default = 0.125, min = 0.0625, max = 1, step = 0.0625 })

return group{ id = "window_frame", name = "Window frame",
	box{ id = "sill", name = "Sill", size = { width, depth, bar } },
	box{ id = "head", name = "Head", size = { width, depth, bar }, transform = { move = { 0, 0, height - bar } } },
	box{ id = "left", name = "Left bar", size = { bar, depth, height } },
	box{ id = "right", name = "Right bar", size = { bar, depth, height }, transform = { move = { width - bar, 0, 0 } } },
}
