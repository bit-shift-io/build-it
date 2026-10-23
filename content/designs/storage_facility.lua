-- The starting storage facility (docs/CONTEXT.md "Storage facility"): a
-- new game places it free at the world centre (Session.newGame). Walls, a
-- stepped gable roof and a chimney on a 3 x 2 tile footprint, with a depot
-- and storage inside and an input and an output port in the south wall.
-- Lengths are in tiles; x east, y south, z up. Runs only through the
-- sandbox (src/game/script/sandbox.lua).
local W, D = 3, 2
local WALL, HEIGHT = 0.125, 1.5
local STEP = 0.25

return group{ id = "root", name = "Storage facility",
	box{ id = "north_wall", name = "North wall", size = { W, WALL, HEIGHT } },
	box{ id = "south_wall", name = "South wall", size = { W, WALL, HEIGHT }, transform = { move = { 0, D - WALL, 0 } } },
	box{ id = "west_wall", name = "West wall", size = { WALL, D, HEIGHT } },
	box{ id = "east_wall", name = "East wall", size = { WALL, D, HEIGHT }, transform = { move = { W - WALL, 0, 0 } } },

	box{ id = "roof_1", name = "Roof", size = { W, D, STEP }, transform = { move = { 0, 0, HEIGHT } } },
	box{ id = "roof_2", name = "Roof", size = { W, D - 2 * STEP, STEP }, transform = { move = { 0, STEP, HEIGHT + STEP } } },
	box{ id = "roof_3", name = "Roof", size = { W, D - 4 * STEP, STEP }, transform = { move = { 0, 2 * STEP, HEIGHT + 2 * STEP } } },
	box{ id = "ridge", name = "Ridge", size = { W, D - 6 * STEP, STEP }, transform = { move = { 0, 3 * STEP, HEIGHT + 3 * STEP } } },
	box{ id = "chimney", name = "Chimney", size = { 0.375, 0.375, 1 }, transform = { move = { 2.25, 0.8125, HEIGHT + STEP } } },

	prefab("depot", { id = "depot", transform = { move = { 0.25, 0.25, 0 } } }),
	prefab("storage", { id = "storage_1", transform = { move = { 0.875, 0.25, 0 } } }),
	prefab("storage", { id = "storage_2", transform = { move = { 1.375, 0.25, 0 } } }),
	prefab("storage", { id = "storage_3", transform = { move = { 1.875, 0.25, 0 } } }),
	prefab("storage", { id = "storage_4", transform = { move = { 2.375, 0.25, 0 } } }),
	prefab("storage", { id = "storage_5", transform = { move = { 0.25, 0.875, 0 } } }),
	prefab("storage", { id = "storage_6", transform = { move = { 0.75, 0.875, 0 } } }),
	prefab("storage", { id = "storage_7", transform = { move = { 1.25, 0.875, 0 } } }),
	prefab("storage", { id = "storage_8", transform = { move = { 1.75, 0.875, 0 } } }),
	prefab("storage", { id = "storage_9", transform = { move = { 2.25, 0.875, 0 } } }),

	prefab("input_port", { id = "input", transform = { move = { 1.5, D - 0.25, 0 } } }),
	prefab("output_port", { id = "output", transform = { move = { 2.25, D - 0.25, 0 } } }),
}
