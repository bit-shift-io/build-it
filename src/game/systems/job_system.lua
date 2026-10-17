-- Pool system for ctx.pools.jobs (docs/CONTEXT.md "Job", "Haul job",
-- "Operator job"). Each step it creates jobs from world state and hands
-- each one straight to the nearest free villager, then steps every job
-- (src/game/jobs/haul.lua, src/game/jobs/operate.lua).
-- A job only exists while a villager holds it, so a job never waits
-- unassigned holding reservations, and no two villagers chase one buffer.
--
-- What gets done, in this order:
--   1. A free villager already carrying a load takes it to the nearest
--      storage facility with room.
--   2. Every function brick with work (FunctionBrick.hasWork) and no
--      operator gets one: the free villager nearest its tile takes its
--      operator job (src/game/jobs/operate.lua), and keeps it while the
--      brick has work.
--   3. Every construction site (src/game/buildings/site.lua) with all its
--      materials delivered gets a builder (src/game/jobs/build.lua), then
--      every site's claimed cost not yet on its way is hauled to it from
--      the facility store holding the claim.
--   4. Every input port with room, of a building whose function bricks
--      consume an item, is fed that item from the nearest output port
--      buffer or storage facility (its storage or output buffers).
--   5. What is left in output port buffers of buildings that are not
--      storage facilities goes to the nearest storage facility with room.
-- Haulers use a storage facility's port tiles, never its footprint: they
-- drop off into its storage at the nearest input port tile and pick up
-- from it at the nearest output port tile, so a facility with no such port
-- is skipped.
-- Pools are walked in order and items in name order (Storage.items), so the
-- same world makes the same jobs. Pure -- no `love.*`.
local Storage = require("src.game.components.storage")
local StorageFacility = require("src.game.components.storage_facility")
local Load = require("src.game.components.load")
local Haul = require("src.game.jobs.haul")
local Operate = require("src.game.jobs.operate")
local Build = require("src.game.jobs.build")
local Site = require("src.game.buildings.site")
local FunctionBrick = require("src.game.components.function_brick")

local JobSystem = {}

-- Whole tiles between two tiles (diagonals count as one).
local function tiles(ax, ay, bx, by)
	return math.max(math.abs(ax - bx), math.abs(ay - by))
end

-- The footprint tile of `b` nearest tile (x, y).
local function nearestTile(b, x, y)
	return math.max(b.tileX, math.min(x, b.tileX + b.width - 1)), math.max(b.tileY, math.min(y, b.tileY + b.depth - 1))
end

-- An endpoint at storage facility `b`'s storage, on the tile of its `kind`
-- port nearest (x, y): "input" to drop off, "output" to pick up. Ties go
-- to the first in port order. Nil when `b` has no such port.
local function atStorage(b, kind, x, y)
	local best, bestD
	for _, port in ipairs(b.ports) do
		if port.kind == kind then
			local d = tiles(port.x, port.y, x, y)
			if not bestD or d < bestD then
				best, bestD = port, d
			end
		end
	end
	return best and { building = b, store = b.storage, x = best.x, y = best.y }
end

local function atPort(b, port)
	return { building = b, store = port.buffer, x = port.x, y = port.y }
end

-- Villagers with no job, in pool order: those carrying a load and those
-- empty-handed.
local function freeVillagers(ctx)
	local loaded, empty = {}, {}
	for _, v in ipairs(ctx.pools.villagers) do
		if not v.job then
			table.insert(Load.empty(v.load) and empty or loaded, v)
		end
	end
	return loaded, empty
end

-- Takes the villager of `free` nearest tile (x, y)'s centre out of the
-- list; ties go to the first in pool order.
local function takeNearest(free, x, y, tile)
	local cx, cy = (x + 0.5) * tile, (y + 0.5) * tile
	local best, bestD
	for i, v in ipairs(free) do
		local d = (v.x - cx) ^ 2 + (v.y - cy) ^ 2
		if not bestD or d < bestD then
			best, bestD = i, d
		end
	end
	return table.remove(free, best)
end

local function open(ctx, job, v)
	table.insert(ctx.pools.jobs, job)
	Haul.start(job, v, ctx)
end

-- The storage facility with room nearest tile (x, y), as a drop endpoint.
local function nearestStorage(ctx, x, y)
	local best, bestD
	for _, b in ipairs(StorageFacility.all(ctx)) do
		if not b.dead and Storage.room(b.storage) > 0 then
			local e = atStorage(b, "input", x, y)
			local d = e and tiles(e.x, e.y, x, y)
			if d and (not bestD or d < bestD) then
				best, bestD = e, d
			end
		end
	end
	return best
end

-- The stores `item` may be hauled out of to feed building `dest`: output
-- buffers of every other building, and the storage of every facility.
local function sources(ctx, dest)
	local list = {}
	for _, b in ipairs(ctx.pools.buildings) do
		if b ~= dest and not b.dead then
			if StorageFacility.is(b) then
				list[#list + 1] = function(x, y)
					return atStorage(b, "output", x, y)
				end
			end
			for _, port in ipairs(b.ports) do
				if port.kind == "output" then
					list[#list + 1] = function()
						return atPort(b, port)
					end
				end
			end
		end
	end
	return list
end

-- The source holding unreserved `item` nearest tile (x, y), for `dest`.
local function nearestSource(ctx, item, dest, x, y)
	local best, bestD
	for _, at in ipairs(sources(ctx, dest)) do
		local e = at(x, y)
		if e and Storage.available(e.store, item) > 0 then
			local d = tiles(e.x, e.y, x, y)
			if not bestD or d < bestD then
				best, bestD = e, d
			end
		end
	end
	return best
end

-- The items `b`'s function bricks consume, in name order.
local function consumed(b)
	local set, items = {}, {}
	for _, fb in ipairs(b.functionBricks) do
		for item in pairs(fb.recipe and fb.recipe.input or {}) do
			if not set[item] then
				set[item] = true
				items[#items + 1] = item
			end
		end
	end
	table.sort(items)
	return items
end

local function storeLoads(ctx, loaded)
	local tile = ctx.config.tileSize
	for _, v in ipairs(loaded) do
		local x, y = math.floor(v.x / tile), math.floor(v.y / tile)
		local dest = nearestStorage(ctx, x, y)
		if dest then
			local n = math.min(v.load.count, Storage.room(dest.store))
			open(ctx, Haul.new(v.load.item, n, nil, dest), v)
		end
	end
end

local function haul(ctx, free, item, source, dest)
	local n = math.min(Storage.available(source.store, item), Storage.room(dest.store), ctx.config.villagers.carryLimit)
	local v = takeNearest(free, source.x, source.y, ctx.config.tileSize)
	open(ctx, Haul.new(item, n, source, dest), v)
end

local function staff(ctx, free)
	for _, b in ipairs(ctx.pools.buildings) do
		for _, fb in ipairs(b.functionBricks) do
			if #free == 0 then
				return
			end
			if not b.dead and not fb.operator and FunctionBrick.hasWork(fb, b, ctx) then
				local v = takeNearest(free, fb.tileX, fb.tileY, ctx.config.tileSize)
				local job = Operate.new(b, fb)
				table.insert(ctx.pools.jobs, job)
				Operate.start(job, v, ctx)
			end
		end
	end
end

-- The source endpoint of a site's `claim`: the facility's output port
-- tile for its storage, else the port whose buffer it is; toward tile
-- (x, y). Nil for a claim on storage when there is no output port.
local function atClaim(claim, x, y)
	local b = claim.building
	local e
	if claim.store == b.storage then
		e = atStorage(b, "output", x, y)
	else
		for _, port in ipairs(b.ports) do
			if port.buffer == claim.store then
				e = atPort(b, port)
			end
		end
	end
	if e then
		e.claim = claim
	end
	return e
end

-- Every site with all its materials delivered, not yet built and with no
-- builder, gets one: the free villager nearest its north-west tile.
local function buildSites(ctx, free)
	for _, site in ipairs(ctx.pools.sites) do
		if #free == 0 then
			return
		end
		if not site.dead and not site.builder and Site.supplied(site) and not Site.built(site, ctx.config) then
			local v = takeNearest(free, site.tileX, site.tileY, ctx.config.tileSize)
			local job = Build.new(site)
			table.insert(ctx.pools.jobs, job)
			Build.start(job, v, ctx)
		end
	end
end

-- Every site's claims not yet on their way are hauled to it: site order,
-- claim order, a carry limit per villager.
local function supplySites(ctx, free)
	local limit = ctx.config.villagers.carryLimit
	for _, site in ipairs(ctx.pools.sites) do
		for _, claim in ipairs(site.dead and {} or site.claims) do
			while #free > 0 and not claim.building.dead and claim.count > claim.taking do
				local n = math.min(claim.count - claim.taking, limit, Storage.room(site.delivered))
				if n <= 0 then
					break
				end
				local source = atClaim(claim, site.tileX, site.tileY)
				if not source then
					break
				end
				local tx, ty = nearestTile(site, source.x, source.y)
				local dest = { building = site, store = site.delivered, x = tx, y = ty }
				open(ctx, Haul.new(claim.item, n, source, dest), takeNearest(free, source.x, source.y, ctx.config.tileSize))
			end
		end
	end
end

local function feedInputs(ctx, free)
	for _, b in ipairs(ctx.pools.buildings) do
		local items = not b.dead and not StorageFacility.is(b) and consumed(b) or {}
		for _, port in ipairs(b.ports) do
			if port.kind == "input" then
				for _, item in ipairs(items) do
					while #free > 0 and Storage.room(port.buffer) > 0 do
						local source = nearestSource(ctx, item, b, port.x, port.y)
						if not source then
							break
						end
						haul(ctx, free, item, source, atPort(b, port))
					end
				end
			end
		end
	end
end

local function clearOutputs(ctx, free)
	for _, b in ipairs(ctx.pools.buildings) do
		if not b.dead and not StorageFacility.is(b) then
			for _, port in ipairs(b.ports) do
				if port.kind == "output" then
					for _, item in ipairs(Storage.items(port.buffer)) do
						while #free > 0 and Storage.available(port.buffer, item) > 0 do
							local dest = nearestStorage(ctx, port.x, port.y)
							if not dest then
								break
							end
							haul(ctx, free, item, atPort(b, port), dest)
						end
					end
				end
			end
		end
	end
end

-- Creates jobs and hands them to free villagers (see the top).
function JobSystem.generate(ctx)
	local loaded, free = freeVillagers(ctx)
	storeLoads(ctx, loaded)
	if #free == 0 then
		return
	end
	staff(ctx, free)
	buildSites(ctx, free)
	supplySites(ctx, free)
	feedInputs(ctx, free)
	clearOutputs(ctx, free)
end

-- Steps every job, in pool order; a job that ends marks itself dead.
function JobSystem.run(ctx)
	for _, job in ipairs(ctx.pools.jobs) do
		if job.kind == "operate" then
			Operate.step(job, ctx)
		elseif job.kind == "build" then
			Build.step(job, ctx)
		else
			Haul.step(job, ctx)
		end
	end
end

function JobSystem.update(ctx)
	JobSystem.generate(ctx)
	JobSystem.run(ctx)
end

-- Despawn sweep for ended jobs: the only place jobs leave the pool.
function JobSystem.despawn(ctx)
	local pool = ctx.pools.jobs
	for i = #pool, 1, -1 do
		if pool[i].dead then
			table.remove(pool, i)
		end
	end
end

return JobSystem
