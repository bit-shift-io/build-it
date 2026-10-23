-- Starter prefab: a pitched (single slope) roof, one wedge high on its west
-- edge and sloping down to the east. Origin at its north-west corner at
-- eaves height; lengths in tiles, x east, y south, z up. Parametric.
local width = UI.number({ label = "Width", default = 2, min = 0.5, max = 12, step = 0.25 })
local depth = UI.number({ label = "Depth", default = 2, min = 0.5, max = 12, step = 0.25 })
local rise = UI.number({ label = "Rise", default = 0.75, min = 0.125, max = 4, step = 0.125 })

return group{ id = "pitched_roof", name = "Pitched roof",
	wedge{ id = "slope", name = "Slope", size = { width, depth, rise } },
}
