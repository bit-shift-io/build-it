-- Wall checks for tests (docs/CONTEXT.md "Walk grid"): whether a figure's
-- square overlaps a blocked stud cell of a finished building, worked out
-- from the building's blueprint, not from Mover. Runs under plain LuaJIT.
local Placement = require("src.game.buildings.placement")
local WalkGrid = require("src.game.buildings.walk_grid")

local Walls = {}

-- The blocked cell of building b's walk grid under record r's square, as
-- x, y on the grid; nil when none. Touching a cell's edge is not
-- overlapping it.
function Walls.under(r, b, config)
	local per = config.walk.cellsPerTile
	local stud = config.tileSize / per
	local grid = Placement.walkGrid(b.blueprint, b.facing)
	local half = r.size / 2
	for sy = math.floor((r.y - half) / stud), math.ceil((r.y + half) / stud) - 1 do
		for sx = math.floor((r.x - half) / stud), math.ceil((r.x + half) / stud) - 1 do
			local x, y = sx - b.tileX * per, sy - b.tileY * per
			if x >= 0 and y >= 0 and x < grid.width and y < grid.depth and not WalkGrid.open(grid, x, y) then
				return x, y
			end
		end
	end
	return nil
end

-- A message naming the first villager of ctx whose square overlaps a
-- blocked cell of any building in ctx.pools.buildings, or nil.
function Walls.villagerInWall(ctx)
	for _, v in ipairs(ctx.pools.villagers) do
		for _, b in ipairs(ctx.pools.buildings) do
			local x, y = Walls.under(v, b, ctx.config)
			if x then
				return string.format(
					"villager %s (%s) at %.1f,%.1f overlaps blocked cell %d,%d of %s",
					tostring(v.id),
					v.job and v.job.kind or "free",
					v.x,
					v.y,
					x,
					y,
					tostring(b.design)
				)
			end
		end
	end
	return nil
end

return Walls
