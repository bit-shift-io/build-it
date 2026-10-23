-- Starter prefab: a round column with a square base and capital. Origin at
-- the north-west ground corner of its base; lengths in tiles, x east, y
-- south, z up. Parametric: height and shaft radius.
local height = UI.number({ label = "Height", default = 1, min = 0.5, max = 6, step = 0.125 })
local radius = UI.number({ label = "Radius", default = 0.1875, min = 0.0625, max = 0.5, step = 0.03125 })

local base = radius * 2 + 0.125
local shaft = height - 0.25

return group{ id = "column", name = "Column",
	box{ id = "base", name = "Base", size = { base, base, 0.125 } },
	cylinder{ id = "shaft", name = "Shaft", radius = radius, height = shaft, transform = { move = { base / 2, base / 2, 0.125 } } },
	box{ id = "capital", name = "Capital", size = { base, base, 0.125 }, transform = { move = { 0, 0, height - 0.125 } } },
}
