-- Role prefab (docs/CONTEXT.md "Role prefab", "Storage brick"): storage
-- for 8 items. Origin at its north-west ground corner; lengths in tiles,
-- x east, y south, z up.
return group{ id = "storage", name = "Storage",
	box{ id = "crate", name = "Crate", size = { 0.5, 0.5, 0.5 } },
	role{ id = "role", storage = 8, transform = { move = { 0.25, 0.25, 0 } } },
}
