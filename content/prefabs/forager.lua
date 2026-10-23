-- Role prefab (docs/CONTEXT.md "Role prefab"): the forager, a function
-- brick that harvests berry bushes. Origin at its north-west ground corner;
-- lengths in tiles, x east, y south, z up.
return group{ id = "forager", name = "Forager",
	box{ id = "basket", name = "Basket", size = { 0.75, 0.25, 0.25 } },
	sphere{ id = "berries", name = "Berries", radius = 0.125, transform = { move = { 0.375, 0.125, 0.3125 } } },
	role{ id = "role", ability = "forager", transform = { move = { 0.375, 0.125, 0 } } },
}
