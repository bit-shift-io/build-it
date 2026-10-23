-- Role prefab (docs/CONTEXT.md "Role prefab"): the pickaxe, a function
-- brick that harvests rocks. Origin at its north-west ground corner;
-- lengths in tiles, x east, y south, z up.
return group{ id = "pickaxe", name = "Pickaxe",
	box{ id = "handle", name = "Handle", size = { 0.125, 0.125, 0.5 }, transform = { move = { 0.3125, 0.0625, 0 } } },
	box{ id = "head", name = "Head", size = { 0.75, 0.125, 0.125 }, transform = { move = { 0, 0.0625, 0.5 } } },
	role{ id = "role", ability = "pickaxe", transform = { move = { 0.375, 0.125, 0 } } },
}
