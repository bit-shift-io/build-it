-- Starter prefab: a door frame, two posts and a lintel round a doorway in
-- a wall running east. Origin at its north-west ground corner; lengths in
-- tiles, x east, y south, z up. Parametric: doorway width and height.
local width = UI.number({ label = "Width", default = 0.5, min = 0.25, max = 4, step = 0.125 })
local height = UI.number({ label = "Height", default = 0.75, min = 0.25, max = 4, step = 0.125 })
local post = UI.number({ label = "Post", default = 0.0625, min = 0.03125, max = 0.25, step = 0.03125 })
local depth = UI.number({ label = "Depth", default = 0.125, min = 0.0625, max = 1, step = 0.0625 })

return group{ id = "door_frame", name = "Door frame",
	box{ id = "left", name = "Left post", size = { post, depth, height } },
	box{ id = "right", name = "Right post", size = { post, depth, height }, transform = { move = { width - post, 0, 0 } } },
	box{ id = "lintel", name = "Lintel", size = { width, depth, post }, transform = { move = { 0, 0, height - post } } },
}
