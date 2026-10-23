-- Starter prefab (a procedural showcase, so a locked script): an arch of
-- blocks round a doorway. Origin at its north-west ground corner, running
-- east; lengths in tiles, x east, y south, z up. Parametric: opening width,
-- height of the piers and block count of the curve.
local width = UI.number({ label = "Opening", default = 1, min = 0.5, max = 4, step = 0.25 })
local pier = UI.number({ label = "Pier height", default = 0.75, min = 0.25, max = 4, step = 0.25 })
local blocks = UI.number({ label = "Blocks", default = 7, min = 3, max = 15, step = 2 })
local depth = 0.25
local post = 0.1875

local parts = {
	box{ id = "left", name = "Left pier", size = { post, depth, pier } },
	box{ id = "right", name = "Right pier", size = { post, depth, pier }, transform = { move = { post + width, 0, 0 } } },
}
local radius = width / 2
local cx, cz = post + radius, pier
for i = 0, blocks - 1 do
	local angle = math.pi * (i + 0.5) / blocks
	local x = cx + math.cos(angle) * radius
	local z = cz + math.sin(angle) * radius
	local size = math.pi * radius / blocks + 0.03125
	parts[#parts + 1] = box{ name = "Block", size = { size, depth, post },
		transform = { move = { x - size / 2, 0, z }, rotate = { 0, -(math.deg(angle) - 90), 0 } } }
end

return group{ id = "arch", name = "Arch", unpack(parts) }
