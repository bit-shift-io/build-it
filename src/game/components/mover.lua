-- Mover component: walks a record across the world from a move intent.
-- Plain data on the record (`record.mover = { speed = <px/s> }`); the owning
-- pool system calls Mover.apply. Never runs itself (docs/ARCHITECTURE.md
-- "Component").
local Vec2 = require("src.core.vec2")
local World = require("src.game.world")

local Mover = {}

local function clamp(v, lo, hi)
	return math.max(lo, math.min(hi, v))
end

-- intent = { x, y }, each in [-1, 1]. Diagonals are normalized so walking
-- diagonally is no faster than walking straight. The world edge stops the
-- record with its whole square still inside the world.
function Mover.apply(record, intent, ctx)
	local dir = Vec2.normalize(intent)
	local step = record.mover.speed * ctx.dt
	local half = record.size / 2
	local w, h = World.pixelSize(ctx.world, ctx.config)
	record.x = clamp(record.x + dir.x * step, half, w - half)
	record.y = clamp(record.y + dir.y * step, half, h - half)
end

return Mover
