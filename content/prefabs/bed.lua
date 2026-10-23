-- Role prefab (docs/CONTEXT.md "Role prefab", "Bed"): a bed, which sleeps
-- one villager. Origin at its north-west ground corner; lengths in tiles,
-- x east, y south, z up.
return group{ id = "bed", name = "Bed",
	box{ id = "frame", name = "Frame", size = { 0.5, 0.5, 0.25 } },
	box{ id = "pillow", name = "Pillow", size = { 0.375, 0.125, 0.0625 }, transform = { move = { 0.0625, 0.0625, 0.25 } } },
	role{ id = "role", ability = "bed", transform = { move = { 0.25, 0.25, 0 } } },
}
