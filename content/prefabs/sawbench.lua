-- Role prefab (docs/CONTEXT.md "Role prefab"): the saw bench, a function
-- brick that turns logs into planks. Origin at its north-west ground
-- corner; lengths in tiles, x east, y south, z up.
return group{ id = "sawbench", name = "Saw bench",
	box{ id = "legs", name = "Legs", size = { 1, 0.5, 0.25 } },
	box{ id = "top", name = "Top", size = { 1, 0.5, 0.125 }, transform = { move = { 0, 0, 0.25 } } },
	box{ id = "blade", name = "Blade", size = { 0.375, 0.0625, 0.25 }, transform = { move = { 0.3125, 0.21875, 0.375 } } },
	role{ id = "role", ability = "sawbench", transform = { move = { 0.5, 0.25, 0 } } },
}
