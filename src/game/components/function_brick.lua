-- Function brick component (docs/CONTEXT.md "Function brick"): one record
-- per function brick of a building, in building.functionBricks. Called by
-- BuildingSystem; never runs itself. Pure -- no `love.*`.
--
-- A harvester ({ ability = "saw"|"pickaxe", kind = <node kind>, progress =
-- <seconds>, node = <reserved node> | nil, state, operator }) does nothing
-- by itself: an operator villager reserves the nearest free node of its
-- kind within the building's reach and harvests it into their load
-- (src/game/jobs/operate.lua). `node` is saved; `operator` is never saved.
--
-- A converter ({ ability, recipe, progress, state = "idle"|"working"|
-- "full", operator = <operator job> | nil }) does nothing by itself: an
-- operator villager runs it (src/game/jobs/operate.lua) while
-- FunctionBrick.hasWork. `operator` is never saved.
--
-- Every record of a placed building has tileX, tileY: the world tile
-- under its brick.
--
-- A planter ({ ability, plants = <node kind>, progress, state, operator })
-- does nothing by itself: its operator readies a seed, picks a free tile in
-- reach (reserved in operator.target) and plants it there. `progress` is
-- saved; `operator` is not.
--
-- A depot ({ ability = "depot", depot = true, state }) makes its building a
-- storage facility (src/game/components/storage_facility.lua) and produces
-- nothing; its step only moves input buffers into storage.
local World = require("src.game.world")
local Harvestable = require("src.game.components.harvestable")
local Storage = require("src.game.components.storage")
local NodeSystem = require("src.game.systems.node_system")

local FunctionBrick = {}

-- The ability of a depot brick (docs/CONTEXT.md "Depot"): it makes its
-- building a storage facility and runs without an operator.
FunctionBrick.DEPOT = "depot"

-- One record per function brick of `version`, in brick order: a depot
-- ({ ability, depot = true, state }), or one that harvests a node kind
-- (config.production.abilities), plants or converts. brickTile(brick) ->
-- x, y (optional) gives each record the world tile under its brick
-- (tileX, tileY), where its operator works.
function FunctionBrick.fromVersion(version, config, brickTile)
	local list = {}
	for _, b in ipairs(version.bricks) do
		local count = #list
		local kind = b.ability and config.production.abilities[b.ability]
		local recipe = b.ability and config.production.recipes[b.ability]
		local plants = b.ability and config.production.planters[b.ability]
		if b.ability == FunctionBrick.DEPOT then
			table.insert(list, { ability = b.ability, depot = true, state = "idle" })
		elseif plants then
			table.insert(list, { ability = b.ability, plants = plants, progress = 0, state = "idle" })
		elseif recipe then
			table.insert(list, { ability = b.ability, recipe = recipe, progress = 0, state = "idle" })
		elseif kind then
			table.insert(list, { ability = b.ability, kind = kind, progress = 0, node = nil, state = "idle" })
		end
		if brickTile and #list > count then
			local fb = list[#list]
			fb.tileX, fb.tileY = brickTile(b)
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
function FunctionBrick.nearestFree(building, kind, ctx)
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

-- The one item and count a converter's recipe takes. A villager's load
-- holds one kind of item, so a recipe has one input item.
function FunctionBrick.recipeInput(recipe)
	local item, n = next(recipe.input)
	assert(next(recipe.input, item) == nil, "a recipe takes one kind of item")
	return item, n
end

-- Whether `fb` has work for an operator (src/game/jobs/operate.lua). A
-- converter has work while one input buffer holds its recipe's input
-- (unreserved) and an output buffer has room. A harvester has work while an
-- output buffer has room and it holds a harvestable node or a free one is in
-- reach. Others run by themselves, so never.
function FunctionBrick.hasWork(fb, building, ctx)
	if fb.kind then
		local node = fb.node and Harvestable.canHarvest(fb.node) and fb.node or FunctionBrick.nearestFree(building, fb.kind, ctx)
		if not node then
			return false
		end
		for _, port in ipairs(building.ports) do
			if port.kind == "output" and Storage.room(port.buffer) > 0 then
				return true
			end
		end
		return false
	end
	if fb.plants then
		return #FunctionBrick.freeTiles(building, ctx) > 0
	end
	if not fb.recipe then
		return false
	end
	local item, n = FunctionBrick.recipeInput(fb.recipe)
	local fed, room = false, false
	for _, port in ipairs(building.ports) do
		if port.kind == "input" then
			fed = fed or Storage.available(port.buffer, item) >= n
		elseif port.kind == "output" then
			room = room or Storage.room(port.buffer) > 0
		end
	end
	return fed and room
end

-- Whether an operator has reserved tile (x, y) to plant on.
local function reserved(ctx, x, y)
	for _, b in ipairs(ctx.pools.buildings) do
		for _, fb in ipairs(b.functionBricks) do
			local t = fb.operator and fb.operator.target
			if t and t[1] == x and t[2] == y then
				return true
			end
		end
	end
	return false
end

-- Whether tile (x, y) is free grass to plant on: no footprint, port tile,
-- node or water, and not reserved by another operator.
function FunctionBrick.canPlantAt(ctx, x, y)
	return x >= 0 and y >= 0 and x < ctx.world.width and y < ctx.world.height
		and World.terrainAt(ctx.world, x, y) == "grass"
		and not World.isBlocked(ctx.world, x, y)
		and not World.nodeAt(ctx.world, x, y)
		and not World.portAt(ctx.world, x, y)
		and not reserved(ctx, x, y)
end

-- The free grass tiles within reach, in row order.
function FunctionBrick.freeTiles(building, ctx)
	local r = FunctionBrick.reach(building.traits, ctx.config)
	local free = {}
	for y = building.tileY - r, building.tileY + building.depth - 1 + r do
		for x = building.tileX - r, building.tileX + building.width - 1 + r do
			if FunctionBrick.canPlantAt(ctx, x, y) then
				table.insert(free, { x, y })
			end
		end
	end
	return free
end

-- A random free grass tile within reach (ctx.rng). Returns x, y or nil.
function FunctionBrick.pickPlantTile(building, ctx)
	local free = FunctionBrick.freeTiles(building, ctx)
	local pick = free[#free > 0 and ctx.rng:int(1, #free) or 1]
	if pick then
		return pick[1], pick[2]
	end
end

-- A depot's step: it makes nothing, it only moves what reached the
-- building's input buffers into its storage while there is room (port
-- order, items in name order), so the inputs free up for more. Items a
-- construction site claimed there stay for their haul.
function FunctionBrick.store(building)
	local storage = building.storage
	for _, port in ipairs(building.ports) do
		if port.kind == "input" then
			for _, item in ipairs(Storage.items(port.buffer)) do
				while Storage.unclaimed(port.buffer, item) > 0 and Storage.room(storage) > 0 do
					Storage.remove(port.buffer, item)
					Storage.add(storage, item)
				end
			end
		end
	end
end

-- One step of work for `fb` in `building`: a depot stores, a planter plants;
-- converters and harvesters do nothing here.
function FunctionBrick.update(fb, building, ctx)
	if fb.depot then
		return FunctionBrick.store(building)
	end
	-- Planters, converters and harvesters work only through their operator
	-- (src/game/jobs/operate.lua).
end

return FunctionBrick
