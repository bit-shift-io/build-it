-- Starter prefab (docs/CONTEXT.md "Prefab"): a straight wall. Origin at its
-- north-west ground corner, running east; lengths in tiles, x east, y
-- south, z up. Parametric: set length, height and thickness per instance.
local length = UI.number({ label = "Length", default = 2, min = 0.25, max = 8, step = 0.25 })
local height = UI.number({ label = "Height", default = 1, min = 0.25, max = 4, step = 0.25 })
local thickness = UI.number({ label = "Thickness", default = 0.125, min = 0.0625, max = 1, step = 0.0625 })

return group{ id = "wall", name = "Wall",
	box{ id = "slab", name = "Slab", size = { length, thickness, height } },
}
