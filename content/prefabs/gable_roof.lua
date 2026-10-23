-- Starter prefab: a gable roof, stepped layers narrowing from the eaves to
-- a ridge along x. Origin at its north-west corner at eaves height; lengths
-- in tiles, x east, y south, z up. Parametric: width (along the ridge),
-- depth (eave to eave) and the height of each step.
local width = UI.number({ label = "Width", default = 3, min = 0.5, max = 12, step = 0.25 })
local depth = UI.number({ label = "Depth", default = 2, min = 0.5, max = 12, step = 0.25 })
local step = UI.number({ label = "Step", default = 0.25, min = 0.0625, max = 1, step = 0.0625 })

local layers = {}
local i = 0
while depth - 2 * i * step > 0.0001 do
	layers[#layers + 1] = box{ name = "Layer", size = { width, depth - 2 * i * step, step },
		transform = { move = { 0, i * step, i * step } } }
	i = i + 1
end

return group{ id = "gable_roof", name = "Gable roof", unpack(layers) }
