-- Pool system for ctx.pools.villagers (docs/CONTEXT.md "Villager"). Calls
-- each record's components explicitly, in a visible order
-- (docs/ARCHITECTURE.md "Systems and frame order"). Villagers have no
-- player intents: they walk the path their walker holds.
local Mover = require("src.game.components.mover")
local Walker = require("src.game.components.walker")
local Animator = require("src.game.components.animator")
local Idle = require("src.game.components.idle")
local Needs = require("src.game.components.needs")
local Sleep = require("src.game.jobs.sleep")

local VillagerSystem = {}

-- One villager's movement for the step: idle life, then its walk.
local function move(v, ctx)
	local fromX, fromY = v.x, v.y
	Idle.update(v, ctx)
	Walker.step(v, ctx)
	local ix, iy = Idle.steer(v, ctx)
	if ix ~= 0 or iy ~= 0 then
		local speed = v.mover.speed
		v.mover.speed = speed * ctx.config.villagers.idle.driftSpeed * math.sqrt(ix * ix + iy * iy)
		Mover.apply(v, { x = ix, y = iy }, ctx)
		v.mover.speed = speed
	end
	Animator.update(v.animator, v.x - fromX, v.y - fromY, ctx.config.character)
	-- Animator.update faces the movement, so a turn counts only on a
	-- step with none.
	if v.idle and v.idle.turnTo and v.x == fromX and v.y == fromY then
		v.animator.facing = v.idle.turnTo
	end
end

-- Needs tick first. A collapsed villager lies where it fell (docs/CONTEXT.md
-- "Collapse"): its path is dropped and it neither walks nor idles.
function VillagerSystem.update(ctx)
	for _, v in ipairs(ctx.pools.villagers) do
		Needs.tick(v.needs, ctx.dt, ctx.config.needs, false, Sleep.rate(v))
		if Needs.collapsed(v.needs) then
			v.walker.path = {}
		else
			move(v, ctx)
		end
	end
end

return VillagerSystem
