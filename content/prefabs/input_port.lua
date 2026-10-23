-- Role prefab (docs/CONTEXT.md "Role prefab", "Port"): an input port,
-- where items are delivered. Its role snaps to the nearest footprint edge
-- at ground level. Origin at its north-west ground corner; lengths in
-- tiles, x east, y south, z up.
return group{ id = "input_port", name = "Input port",
	box{ id = "pad", name = "Pad", size = { 0.5, 0.25, 0.0625 } },
	role{ id = "role", port = "input", transform = { move = { 0.25, 0.125, 0 } } },
}
