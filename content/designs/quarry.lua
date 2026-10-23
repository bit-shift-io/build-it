-- Starter building (docs/CONTEXT.md "Blueprint"): the quarry, a pickaxe that breaks rocks nearby; stone leaves by the output port.
-- Declarative: a stone floor and low stone walls, a plank roof and role
-- prefabs, no code; lean enough for the starting stockpile. Lengths in
-- tiles; x east, y south, z up. Runs only through the sandbox.
return group{ id = "root", name = "Quarry",
	box{ id = "floor", name = "Floor", size = { 2, 2, 0.0625 }, material = { name = "stone" } },
	prefab("wall", { id = "north_wall", material = { name = "stone" }, params = { length = 2, height = 0.5, thickness = 0.0625 }, transform = { move = { 0, 0, 0.0625 } } }),
	box{ id = "west_wall", name = "West wall", size = { 0.0625, 2, 0.5 }, material = { name = "stone" }, transform = { move = { 0, 0, 0.0625 } } },
	box{ id = "east_wall", name = "East wall", size = { 0.0625, 2, 0.5 }, material = { name = "stone" }, transform = { move = { 1.9375, 0, 0.0625 } } },
	prefab("window_frame", { id = "window", transform = { move = { 0.625, 0, 0.125 } } }),
	prefab("door_frame", { id = "door", transform = { move = { 0.75, 1.875, 0.0625 } } }),
	prefab("pitched_roof", { id = "roof", params = { width = 2, depth = 2, rise = 0.125 }, transform = { move = { 0, 0, 0.5625 } } }),
	prefab("pickaxe", { id = "pickaxe_1", transform = { move = { 0.5, 0.5, 0.0625 } } }),
	prefab("output_port", { id = "output_port", transform = { move = { 1.25, 1.75, 0 } } }),
}
