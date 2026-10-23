-- Role prefab (docs/CONTEXT.md "Role prefab", "Port"): an output port,
-- where items are collected. Its role snaps to the nearest footprint edge
-- at ground level. Origin at its north-west ground corner; lengths in
-- tiles, x east, y south, z up.
return group{ id = "output_port", name = "Output port",
	box{ id = "pad", name = "Pad", size = { 0.5, 0.25, 0.0625 } },
	role{ id = "role", port = "output", transform = { move = { 0.25, 0.125, 0 } } },
}
