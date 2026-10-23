-- The script builder's test design (src/app/screens/script_builder.lua):
-- a box and a scaled sphere on top. Lengths are in tiles; x east, y south,
-- z up. Runs only through the sandbox (src/game/script/sandbox.lua).
local height = UI.number({ default = 1, step = 0.25, min = 0.25 })

return group{ id = "root", name = "Test design",
	box{ id = "base", name = "Base", size = { 2, 1.5, height } },
	sphere{ id = "dome", name = "Dome", radius = 0.6,
		transform = { move = { 1, 0.75, height }, scale = { 1.4, 1, 0.8 } } },
}
