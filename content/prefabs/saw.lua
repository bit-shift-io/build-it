-- Role prefab (docs/CONTEXT.md "Role prefab"): the saw, a function brick
-- that harvests trees. Its look is free to change; its role stays. Origin
-- at its north-west ground corner; lengths in tiles, x east, y south, z up.
return group{ id = "saw", name = "Saw",
	box{ id = "bench", name = "Bench", size = { 0.75, 0.25, 0.25 } },
	box{ id = "blade", name = "Blade", size = { 0.5, 0.0625, 0.375 }, transform = { move = { 0.125, 0.09375, 0.25 } } },
	role{ id = "role", ability = "saw", transform = { move = { 0.375, 0.125, 0 } } },
}
