-- Role prefab (docs/CONTEXT.md "Role prefab", "Canteen"): a canteen, an
-- eating spot. Origin at its north-west ground corner; lengths in tiles,
-- x east, y south, z up.
return group{ id = "canteen", name = "Canteen",
	box{ id = "table", name = "Table", size = { 0.5, 0.5, 0.25 } },
	sphere{ id = "pot", name = "Pot", radius = 0.125, transform = { move = { 0.25, 0.25, 0.3125 } } },
	role{ id = "role", ability = "canteen", transform = { move = { 0.25, 0.25, 0 } } },
}
