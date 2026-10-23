-- Role prefab (docs/CONTEXT.md "Role prefab"): the planter, a function
-- brick that plants saplings. Origin at its north-west ground corner;
-- lengths in tiles, x east, y south, z up.
return group{ id = "planter", name = "Planter",
	box{ id = "bed", name = "Soil bed", size = { 0.5, 0.5, 0.25 } },
	sphere{ id = "sapling", name = "Sapling", radius = 0.125, transform = { move = { 0.25, 0.25, 0.375 } } },
	role{ id = "role", ability = "planter", transform = { move = { 0.25, 0.25, 0 } } },
}
