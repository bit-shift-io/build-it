-- Role prefab (docs/CONTEXT.md "Role prefab", "Depot"): the depot, which
-- makes its building a storage facility. Origin at its north-west ground
-- corner; lengths in tiles, x east, y south, z up.
return group{ id = "depot", name = "Depot",
	box{ id = "crate", name = "Crate", size = { 0.5, 0.5, 0.5 } },
	box{ id = "lid", name = "Lid", size = { 0.5625, 0.5625, 0.0625 }, transform = { move = { -0.03125, -0.03125, 0.5 } } },
	role{ id = "role", ability = "depot", transform = { move = { 0.25, 0.25, 0 } } },
}
