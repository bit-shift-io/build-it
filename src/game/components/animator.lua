-- Animator component: which baked character frame a record shows. Plain
-- data on the record (`record.animator`); the owning pool system calls
-- Animator.update with how far the record moved this step. Pure.
local Character = require("src.game.props.character")

local Animator = {}

local COUNT = #Character.DIRECTIONS

-- The index into Character.DIRECTIONS nearest the velocity (dx, dy), x east
-- and y south. Directions run clockwise from north, 45 degrees apart.
function Animator.direction(dx, dy)
	local angle = math.atan2(dx, -dy) -- 0 at north, clockwise
	return math.floor(angle / (2 * math.pi / COUNT) + 0.5) % COUNT + 1
end

-- A record's animator, standing idle and facing south (toward the camera).
--   { facing = <index into Character.DIRECTIONS>, frame, distance }
-- distance is how far, in px, the current walk has covered.
function Animator.new()
	return { facing = 5, frame = Character.IDLE, distance = 0 }
end

-- Advances by this step's movement (dx, dy) in px. Moving faces the
-- movement direction and shows the walk frame for the distance walked so
-- far, one frame per cfg.walkFrameDistance px. No movement shows the idle
-- frame, keeps the facing, and restarts the walk cycle.
-- cfg = config.character.
function Animator.update(animator, dx, dy, cfg)
	if dx == 0 and dy == 0 then
		animator.frame = Character.IDLE
		animator.distance = 0
		return
	end
	animator.facing = Animator.direction(dx, dy)
	animator.distance = animator.distance + math.sqrt(dx * dx + dy * dy)
	local step = math.ceil(animator.distance / cfg.walkFrameDistance) - 1
	animator.frame = Character.WALK[step % #Character.WALK + 1]
end

return Animator
