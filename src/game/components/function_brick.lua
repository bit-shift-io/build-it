-- Function brick component (docs/CONTEXT.md "Function brick"): one record
-- per harvesting brick (a saw or pickaxe) of a building, in
-- building.functionBricks. Each works on its own: it reserves the nearest
-- free node of its kind within the building's reach and harvests it one
-- cycle at a time into the building (Ports.push), in parallel with the
-- others. Called by BuildingSystem; never runs itself. Pure -- no `love.*`.
--
--   { ability = "saw"|"pickaxe", kind = <node kind>, progress = <seconds>,
--     node = <reserved node> | nil, state = "idle"|"working"|"full" }
local World = require("src.game.world")
local Harvestable = require("src.game.components.harvestable")
local Ports = require("src.game.components.ports")
local NodeSystem = require("src.game.systems.node_system")

local FunctionBrick = {}

-- One record per brick of `version` whose ability harvests a node kind
-- (config.production.abilities), in brick order.
function FunctionBrick.fromVersion(version, config)
	local list = {}
	for _, b in ipairs(version.bricks) do
		local kind = b.ability and config.production.abilities[b.ability]
		local recipe = b.ability and config.production.recipes[b.ability]
		local plants = b.ability and config.production.planters[b.ability]
		if plants then
			table.insert(list, { ability = b.ability, plants = plants, progress = 0, state = "idle" })
		elseif recipe then
			table.insert(list, { ability = b.ability, recipe = recipe, progress = 0, converting = false, state = "idle" })
		elseif kind then
			table.insert(list, { ability = b.ability, kind = kind, progress = 0, node = nil, state = "idle" })
		end
	end
	return list
end

-- Seconds per item for a function brick of a building with `traits`.
function FunctionBrick.cycle(traits, config, base)
	local p = config.production
	return (base or p.harvestCycle) / math.max(p.minSpeed, 1 + traits.productivity * p.productivityStep)
end

-- How many tiles from its footprint a building with `traits` reaches.
function FunctionBrick.reach(traits, config)
	local p = config.production
	return p.reachBase + math.floor(traits.reach * p.reachPerPoint)
end

-- Whole tiles from tile (x, y) to the nearest footprint tile of `building`.
local function distance(building, x, y)
	local dx = math.max(building.tileX - x, 0, x - (building.tileX + building.width - 1))
	local dy = math.max(building.tileY - y, 0, y - (building.tileY + building.depth - 1))
	return math.max(dx, dy)
end

-- The nearest free, harvestable node of `kind` within reach; ties go to
-- the first in row order (north to south, west to east).
local function nearestFree(building, kind, ctx)
	local r = FunctionBrick.reach(building.traits, ctx.config)
	local best, bestD
	for y = building.tileY - r, building.tileY + building.depth - 1 + r do
		for x = building.tileX - r, building.tileX + building.width - 1 + r do
			local n = World.nodeAt(ctx.world, x, y)
			if n and n.kind == kind and Harvestable.canHarvest(n) and NodeSystem.isFree(n) then
				local d = distance(building, x, y)
				if not bestD or d < bestD then
					best, bestD = n, d
				end
			end
		end
	end
	return best
end

-- One step for a converter: starts a cycle when the recipe's inputs are
-- there (consuming them), and delivers the product when the cycle ends,
-- stalling while the building has no room for it.
function FunctionBrick.convert(fb, building, ctx)
	local recipe = fb.recipe
	if not fb.converting then
		if not Ports.canPull(building, recipe.input) then
			fb.state = "idle"
			return
		end
		Ports.pull(building, recipe.input)
		fb.converting = true
		fb.progress = 0
	end
	local cycle = FunctionBrick.cycle(building.traits, ctx.config, recipe.cycle)
	fb.progress = math.min(fb.progress + ctx.dt, cycle)
	if fb.progress < cycle then
		fb.state = "working"
	elseif Ports.hasRoom(building) then
		Ports.push(building, recipe.output)
		fb.converting = false
		fb.progress = 0
		fb.state = "idle"
	else
		fb.state = "full"
	end
end

-- A random free grass tile within reach: no footprint, port tile, node or
-- water. Returns x, y or nil.
local function freeTile(building, ctx)
	local r = FunctionBrick.reach(building.traits, ctx.config)
	local free = {}
	for y = building.tileY - r, building.tileY + building.depth - 1 + r do
		for x = building.tileX - r, building.tileX + building.width - 1 + r do
			if x >= 0 and y >= 0 and x < ctx.world.width and y < ctx.world.height
				and World.terrainAt(ctx.world, x, y) == "grass"
				and not World.isBlocked(ctx.world, x, y)
				and not World.nodeAt(ctx.world, x, y)
				and not World.portAt(ctx.world, x, y)
			then
				table.insert(free, { x, y })
			end
		end
	end
	local pick = free[#free > 0 and ctx.rng:int(1, #free) or 1]
	if pick then
		return pick[1], pick[2]
	end
end

-- One step for a planter: plants one sapling each cycle on a free tile in
-- reach, waiting (progress held at a full cycle) while none is free.
function FunctionBrick.plant(fb, building, ctx)
	local cycle = FunctionBrick.cycle(building.traits, ctx.config, ctx.config.production.plantCycle)
	fb.progress = math.min(fb.progress + ctx.dt, cycle)
	if fb.progress < cycle then
		fb.state = "working"
		return
	end
	local x, y = freeTile(building, ctx)
	if not x then
		fb.state = "idle"
		return
	end
	NodeSystem.plant(ctx, fb.plants, x, y)
	fb.progress = 0
	fb.state = "working"
end

-- One step of work for `fb` in `building`: stalls while the building has no
-- room, finds a node when it has none, and moves one item per cycle.
function FunctionBrick.update(fb, building, ctx)
	if fb.plants then
		return FunctionBrick.plant(fb, building, ctx)
	end
	if fb.recipe then
		return FunctionBrick.convert(fb, building, ctx)
	end
	if not Ports.hasRoom(building) then
		fb.state = "full"
		return
	end
	if not fb.node then
		local n = nearestFree(building, fb.kind, ctx)
		if not n then
			fb.state = "idle"
			fb.progress = 0
			return
		end
		NodeSystem.reserve(n, fb)
		fb.progress = 0
	end
	fb.state = "working"
	local cycle = FunctionBrick.cycle(building.traits, ctx.config)
	fb.progress = fb.progress + ctx.dt
	while fb.progress >= cycle do
		if not Ports.hasRoom(building) then
			fb.progress = cycle
			fb.state = "full"
			return
		end
		fb.progress = fb.progress - cycle
		Ports.push(building, Harvestable.take(fb.node, ctx.config))
		if not Harvestable.canHarvest(fb.node) then
			NodeSystem.release(fb.node)
			fb.progress = 0
			return
		end
	end
end

return FunctionBrick
