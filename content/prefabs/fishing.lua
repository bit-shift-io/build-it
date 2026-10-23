-- Role prefab (docs/CONTEXT.md "Role prefab"): the fishing brick, a
-- function brick that fishes water. Origin at its north-west ground corner;
-- lengths in tiles, x east, y south, z up.
return group{ id = "fishing", name = "Fishing",
	box{ id = "tub", name = "Tub", size = { 0.75, 0.25, 0.25 } },
	box{ id = "rod", name = "Rod", size = { 0.0625, 0.0625, 0.5 }, transform = { move = { 0.625, 0.09375, 0.25 } } },
	role{ id = "role", ability = "fishing", transform = { move = { 0.375, 0.125, 0 } } },
}
