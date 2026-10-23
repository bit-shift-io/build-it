-- Starter prefab (a procedural showcase, so a locked script): a fence of
-- posts and two rails, running east. Origin at its north-west ground
-- corner; lengths in tiles, x east, y south, z up. Parametric: length,
-- height and post spacing.
local length = UI.number({ label = "Length", default = 2, min = 0.5, max = 12, step = 0.25 })
local height = UI.number({ label = "Height", default = 0.5, min = 0.25, max = 2, step = 0.125 })
local spacing = UI.number({ label = "Post spacing", default = 0.5, min = 0.25, max = 2, step = 0.125 })
local post = 0.0625

local parts = {
	box{ id = "low_rail", name = "Low rail", size = { length, post / 2, post }, transform = { move = { 0, post / 4, height * 0.3 } } },
	box{ id = "high_rail", name = "High rail", size = { length, post / 2, post }, transform = { move = { 0, post / 4, height * 0.75 } } },
}
local count = math.max(1, math.floor(length / spacing + 0.5))
for i = 0, count do
	local x = math.min(i * length / count, length - post)
	parts[#parts + 1] = box{ name = "Post", size = { post, post, height }, transform = { move = { x, 0, 0 } } }
end

return group{ id = "fence", name = "Fence", unpack(parts) }
