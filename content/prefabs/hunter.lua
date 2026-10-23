-- Role prefab (docs/CONTEXT.md "Role prefab"): the hunter, a function
-- brick that hunts deer. Origin at its north-west ground corner; lengths
-- in tiles, x east, y south, z up.
return group{ id = "hunter", name = "Hunter",
	box{ id = "rack", name = "Rack", size = { 0.75, 0.25, 0.25 } },
	box{ id = "bow", name = "Bow", size = { 0.0625, 0.0625, 0.5 }, transform = { move = { 0.125, 0.09375, 0.25 } } },
	role{ id = "role", ability = "hunter", transform = { move = { 0.375, 0.125, 0 } } },
}
