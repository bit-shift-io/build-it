-- An operator job (docs/CONTEXT.md "Operator job", ADR 0003): one villager
-- runs one function brick. The job is sticky: when the villager finishes a
-- cycle it starts the next while the brick still has work
-- (FunctionBrick.hasWork), and lets go when it has none. Plain data in
-- ctx.pools.jobs; src/game/systems/job_system.lua creates, assigns and
-- steps it. Pure -- no `love.*`.
--
--   job = { kind = "operate", building, brick = <function brick record>,
--           work = <work>, villager = <villager> | nil,
--           stage = <name of a step of work>, dead = true when ended }
--
-- The framework walks the villager, ends the job when the building is
-- gone or a walk has no route, and repeats cycles. A work holds what a kind
-- of brick does, as named steps:
--   work.begin(job, ctx)     -- starts a cycle: sets job.stage, walks
--   work[job.stage](job, ctx) -- each step once the villager stands still
--   work.release(job)        -- (optional) frees what the job holds
-- A step calls Operate.walkTo to move on and Operate.done when a cycle is
-- over. The villager keeps whatever it carries when the job ends, and the
-- brick's `operator` is the job while it is held.
local FunctionBrick = require("src.game.components.function_brick")
local Walker = require("src.game.components.walker")
local Storage = require("src.game.components.storage")
local Load = require("src.game.components.load")
local Harvestable = require("src.game.components.harvestable")
local NodeSystem = require("src.game.systems.node_system")
local World = require("src.game.world")

local Operate = {}

-- Ends `job`: the work releases what it holds, the brick and the villager
-- are free again.
function Operate.finish(job)
	if job.dead then
		return
	end
	if job.work.release then
		job.work.release(job)
	end
	job.dead = true
	job.brick.operator = nil
	if job.villager then
		job.villager.job = nil
	end
end

-- Sends the operator to tile (x, y) under `stage`. False (and the job
-- ended) when there is no route.
function Operate.walkTo(job, ctx, stage, x, y)
	job.stage = stage
	if not Walker.goTo(job.villager, ctx, x, y) then
		Operate.finish(job)
		return false
	end
	return true
end

-- A cycle is over: the next starts while the brick has work, else the job
-- ends.
function Operate.done(job, ctx)
	if FunctionBrick.hasWork(job.brick, job.building, ctx) then
		job.work.begin(job, ctx)
	else
		Operate.finish(job)
	end
end

-- Gives `job` to villager `v` and starts its first cycle.
function Operate.start(job, v, ctx)
	job.villager = v
	v.job = job
	job.brick.operator = job
	job.work.begin(job, ctx)
	return not job.dead
end

-- One step, after the villager walked: ends the job when its building is
-- gone; otherwise runs the work's current step once the villager stands
-- still.
function Operate.step(job, ctx)
	if job.dead then
		return
	end
	if job.building.dead then
		return Operate.finish(job)
	end
	if not Walker.idle(job.villager.walker) then
		return
	end
	job.work[job.stage](job, ctx)
end

-- Converter work (a saw bench): take the recipe input from an input
-- buffer, carry it to the brick's tile, wait one cycle, carry the product
-- to an output buffer. One output room (job.out) is reserved before the
-- operator heads for the input, so it never holds an item with nowhere to
-- put it; the input is taken on pick-up, not reserved on the way.
local Convert = {}

-- The port of `kind` nearest the brick's tile that ok(port) accepts; ties
-- go to the first in port order.
local function nearestPort(job, kind, ok)
	local fb, best, bestD = job.brick, nil, nil
	for _, port in ipairs(job.building.ports) do
		if port.kind == kind and ok(port) then
			local d = math.max(math.abs(port.x - fb.tileX), math.abs(port.y - fb.tileY))
			if not bestD or d < bestD then
				best, bestD = port, d
			end
		end
	end
	return best
end

function Convert.begin(job, ctx)
	local item, n = FunctionBrick.recipeInput(job.brick.recipe)
	local port = nearestPort(job, "input", function(p)
		return Storage.available(p.buffer, item) >= n
	end)
	local out = nearestPort(job, "output", function(p)
		return Storage.room(p.buffer) > 0
	end)
	if not port or not out then
		return Operate.finish(job)
	end
	job.port, job.out = port, out
	Storage.reserveRoom(out.buffer, 1)
	Operate.walkTo(job, ctx, "toInput", port.x, port.y)
end

function Convert.toInput(job, ctx)
	local item, n = FunctionBrick.recipeInput(job.brick.recipe)
	local store = job.port.buffer
	job.port = nil
	if Storage.available(store, item) < n then
		return Operate.finish(job)
	end
	for _ = 1, n do
		Storage.remove(store, item)
	end
	Load.add(job.villager.load, item, n)
	Operate.walkTo(job, ctx, "toBrick", job.brick.tileX, job.brick.tileY)
end

function Convert.toBrick(job, ctx)
	job.stage = "working"
	job.brick.progress = 0
	Convert.working(job, ctx)
end

function Convert.working(job, ctx)
	local fb, building = job.brick, job.building
	local cycle = FunctionBrick.cycle(building.traits, ctx.config, fb.recipe.cycle)
	fb.progress = math.min(fb.progress + ctx.dt, cycle)
	if fb.progress < cycle then
		fb.state = "working"
		return
	end
	local load = job.villager.load
	Load.remove(load, load.count)
	Load.add(load, fb.recipe.output, 1)
	fb.progress = 0
	fb.state = "idle"
	Operate.walkTo(job, ctx, "toOutput", job.out.x, job.out.y)
end

function Convert.toOutput(job, ctx)
	local store, load = job.out.buffer, job.villager.load
	Storage.releaseRoom(store, 1)
	job.out = nil
	Storage.add(store, load.item)
	Load.remove(load, 1)
	Operate.done(job, ctx)
end

function Convert.release(job)
	if job.out then
		Storage.releaseRoom(job.out.buffer, 1)
	end
	job.port, job.out = nil, nil
	job.brick.state = "idle"
end

-- Harvester work (a saw or pickaxe): reserve a free node in reach, stand
-- beside it (nodes block their tile), harvest one item per cycle into the
-- load, and carry the load to an output port when it is full, the port has
-- no more room, or no node is left. Each item's room at that port
-- (job.port, job.reserved in all) is reserved just before it is harvested,
-- so saws sharing a port work side by side and no item is held without
-- room to put it. The brick's node is held while the job runs.
local Harvest = {}

-- The tile beside node `n` the villager walks to: the free neighbour nearest
-- the villager; ties go to the first in row order. Nil when walled in.
local function standTile(job, ctx, n)
	local tile, v = ctx.config.tileSize, job.villager
	local best, bestD
	for dy = -1, 1 do
		for dx = -1, 1 do
			local x, y = n.tileX + dx, n.tileY + dy
			if (dx ~= 0 or dy ~= 0) and x >= 0 and y >= 0 and x < ctx.world.width and y < ctx.world.height
				and not World.isBlocked(ctx.world, x, y, true)
			then
				local d = (v.x - (x + 0.5) * tile) ^ 2 + (v.y - (y + 0.5) * tile) ^ 2
				if not bestD or d < bestD then
					best, bestD = { x, y }, d
				end
			end
		end
	end
	if best then
		return best[1], best[2]
	end
end

-- Whether room for one more item can be reserved: at the port the load is
-- already bound for, else at the output with room nearest the brick (which
-- becomes job.port).
local function hasSlot(job)
	if job.port and (Storage.room(job.port.buffer) > 0 or job.reserved > 0) then
		return Storage.room(job.port.buffer) > 0
	end
	job.port = nearestPort(job, "output", function(p)
		return Storage.room(p.buffer) > 0
	end)
	job.reserved = 0
	return job.port ~= nil
end

-- Carries the load to job.port, where its room is reserved.
function Harvest.deliver(job, ctx)
	if not job.port or Load.empty(job.villager.load) then
		return Operate.finish(job)
	end
	job.brick.state = "idle"
	Operate.walkTo(job, ctx, "toOutput", job.port.x, job.port.y)
end

function Harvest.begin(job, ctx)
	local fb, load = job.brick, job.villager.load
	local item = ctx.config.nodes[fb.kind].item
	if fb.node and not Harvestable.canHarvest(fb.node) then
		NodeSystem.release(fb.node)
	end
	if Load.room(load) == 0 or (load.item and load.item ~= item) or not hasSlot(job) then
		return Harvest.deliver(job, ctx)
	end
	if not fb.node then
		local n = FunctionBrick.nearestFree(job.building, fb.kind, ctx)
		if not n then
			if Load.empty(load) then
				return Operate.finish(job)
			end
			return Harvest.deliver(job, ctx)
		end
		NodeSystem.reserve(n, fb)
		fb.progress = 0
	end
	local x, y = standTile(job, ctx, fb.node)
	if not x then
		return Operate.finish(job)
	end
	Operate.walkTo(job, ctx, "toNode", x, y)
end

-- Arrived beside the node (or it died on the way: pick again).
function Harvest.toNode(job, ctx)
	if not job.brick.node or not Harvestable.canHarvest(job.brick.node) then
		return Harvest.begin(job, ctx)
	end
	job.stage = "harvesting"
	Harvest.harvesting(job, ctx)
end

function Harvest.harvesting(job, ctx)
	local fb, load = job.brick, job.villager.load
	if not fb.node or not Harvestable.canHarvest(fb.node) then
		fb.progress = 0
		return Harvest.begin(job, ctx)
	end
	fb.state = "working"
	local cycle = FunctionBrick.cycle(job.building.traits, ctx.config)
	fb.progress = fb.progress + ctx.dt
	while fb.progress >= cycle do
		fb.progress = fb.progress - cycle
		if not hasSlot(job) then
			fb.progress = 0
			return Harvest.begin(job, ctx)
		end
		Storage.reserveRoom(job.port.buffer, 1)
		job.reserved = job.reserved + 1
		Load.add(load, Harvestable.take(fb.node, ctx.config), 1)
		if not Harvestable.canHarvest(fb.node) then
			NodeSystem.release(fb.node)
			fb.progress = 0
			return Harvest.begin(job, ctx)
		end
		if Load.room(load) == 0 then
			fb.progress = 0
			return Harvest.begin(job, ctx)
		end
	end
end

function Harvest.toOutput(job, ctx)
	local store, load = job.port.buffer, job.villager.load
	if job.reserved > 0 then
		Storage.releaseRoom(store, job.reserved)
	end
	job.port, job.reserved = nil, nil
	local n = math.min(load.count, Storage.room(store))
	for _ = 1, n do
		Storage.add(store, load.item)
	end
	Load.remove(load, n)
	Operate.done(job, ctx)
end

function Harvest.release(job)
	if job.port and job.reserved > 0 then
		Storage.releaseRoom(job.port.buffer, job.reserved)
	end
	job.port, job.reserved = nil, nil
	if job.brick.node then
		NodeSystem.release(job.brick.node)
	end
	job.brick.progress = 0
	job.brick.state = "idle"
end

-- Planter work: ready a seed at the brick (one plant cycle), pick and
-- reserve a free tile in reach (job.target; FunctionBrick.canPlantAt skips
-- reserved tiles), walk there, plant a sapling and walk back. The
-- reservation lives while the job does.
local Plant = {}

function Plant.begin(job, ctx)
	Operate.walkTo(job, ctx, "toBrick", job.brick.tileX, job.brick.tileY)
end

function Plant.toBrick(job)
	job.brick.progress = 0
	job.stage = "seeding"
end

function Plant.seeding(job, ctx)
	local fb = job.brick
	local cycle = FunctionBrick.cycle(job.building.traits, ctx.config, ctx.config.production.plantCycle)
	fb.progress = math.min(fb.progress + ctx.dt, cycle)
	fb.state = "working"
	if fb.progress < cycle then
		return
	end
	local x, y = FunctionBrick.pickPlantTile(job.building, ctx)
	if not x then
		return Operate.finish(job)
	end
	job.target = { x, y }
	Operate.walkTo(job, ctx, "toTile", x, y)
end

-- Arrived: plants unless something took the tile meanwhile.
function Plant.toTile(job, ctx)
	local x, y = job.target[1], job.target[2]
	job.target = nil
	job.brick.progress = 0
	if World.terrainAt(ctx.world, x, y) == "grass" and not World.isBlocked(ctx.world, x, y)
		and not World.nodeAt(ctx.world, x, y) and not World.portAt(ctx.world, x, y)
	then
		NodeSystem.plant(ctx, job.brick.plants, x, y)
	end
	Operate.walkTo(job, ctx, "back", job.brick.tileX, job.brick.tileY)
end

function Plant.back(job, ctx)
	Operate.done(job, ctx)
end

function Plant.release(job)
	job.target = nil
	job.brick.state = "idle"
end

Operate.works = { convert = Convert, harvest = Harvest, plant = Plant }

-- The work of function brick `fb`, or nil when it needs no operator yet.
local function workFor(fb)
	if fb.plants then
		return Operate.works.plant
	elseif fb.recipe then
		return Operate.works.convert
	elseif fb.kind then
		return Operate.works.harvest
	end
end

-- A new open operator job for brick `fb` of `building`.
function Operate.new(building, fb)
	return { kind = "operate", building = building, brick = fb, work = assert(workFor(fb), "no operator work for " .. tostring(fb.ability)) }
end

return Operate
