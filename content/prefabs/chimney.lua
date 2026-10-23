-- Starter prefab: a chimney, a square stack with a lip. Origin at its
-- north-west base corner; lengths in tiles, x east, y south, z up.
-- Parametric: height and stack width.
local height = UI.number({ label = "Height", default = 1, min = 0.25, max = 4, step = 0.125 })
local size = UI.number({ label = "Size", default = 0.375, min = 0.125, max = 1, step = 0.0625 })

return group{ id = "chimney", name = "Chimney",
	box{ id = "stack", name = "Stack", size = { size, size, height } },
	box{ id = "lip", name = "Lip", size = { size + 0.125, size + 0.125, 0.0625 }, transform = { move = { -0.0625, -0.0625, height } } },
}
