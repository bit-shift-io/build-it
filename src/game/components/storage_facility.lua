-- Storage facilities (docs/CONTEXT.md "Storage facility", "Depot"): the
-- buildings with a depot, the colony's bank. What a facility holds is its
-- storage and its port buffers together. Placement claims its cost in
-- them for a construction site, the facility nearest the spot first. Pure -- no `love.*`.
local Storage = require("src.game.components.storage")

local StorageFacility = {}

-- Whether `building` has a depot.
function StorageFacility.is(building)
	for _, fb in ipairs(building.functionBricks) do
		if fb.depot then
			return true
		end
	end
	return false
end

-- Every storage facility in ctx.pools.buildings, in pool order.
function StorageFacility.all(ctx)
	local list = {}
	for _, b in ipairs(ctx.pools.buildings) do
		if StorageFacility.is(b) then
			list[#list + 1] = b
		end
	end
	return list
end

-- The stores of facility `b` in the order spending takes from them: its
-- storage, then its port buffers in port order.
local function stores(b)
	local list = { b.storage }
	for _, port in ipairs(b.ports) do
		list[#list + 1] = port.buffer
	end
	return list
end

local function percent(held, capacity)
	return math.floor(held * 100 / capacity)
end

-- { held, capacity, percent } for facility `b`'s storage alone (port buffers
-- and incoming haul reservations don't count), percent a whole number
-- rounded down; nil when it has no capacity.
function StorageFacility.fill(b)
	local capacity = b.storage.capacity
	if not capacity or capacity <= 0 then
		return nil
	end
	local held = Storage.total(b.storage)
	return { held = held, capacity = capacity, percent = percent(held, capacity) }
end

-- The colony-wide fill percent: held over capacity summed across live
-- facilities; nil when their capacity is 0.
function StorageFacility.totalFill(ctx)
	local held, capacity = 0, 0
	for _, b in ipairs(StorageFacility.all(ctx)) do
		local f = not b.dead and StorageFacility.fill(b)
		if f then
			held = held + f.held
			capacity = capacity + f.capacity
		end
	end
	if capacity == 0 then
		return nil
	end
	return percent(held, capacity)
end

-- { [item] = n } over every store of every facility: what each(store,
-- item) counts.
local function sum(ctx, each)
	local totals = {}
	for _, b in ipairs(StorageFacility.all(ctx)) do
		for _, store in ipairs(stores(b)) do
			for item in pairs(store.counts) do
				local n = each(store, item)
				if n > 0 then
					totals[item] = (totals[item] or 0) + n
				end
			end
		end
	end
	return totals
end

-- { [item] = n }: everything every facility holds that no construction
-- site claimed -- what placement may still spend.
function StorageFacility.totals(ctx)
	return sum(ctx, Storage.unclaimed)
end

-- { [item] = n }: what construction sites claimed and is still in storage.
function StorageFacility.claimed(ctx)
	return sum(ctx, function(store, item)
		return store.claimed and store.claimed[item] or 0
	end)
end

-- Whether the facilities together hold every item of `cost` ({ [item] = n }).
function StorageFacility.has(ctx, cost)
	local totals = StorageFacility.totals(ctx)
	for item, n in pairs(cost) do
		if (totals[item] or 0) < n then
			return false
		end
	end
	return true
end

-- Whole tiles from tile (x, y) to the nearest footprint tile of `b`.
local function distance(b, x, y)
	local dx = math.max(b.tileX - x, 0, x - (b.tileX + b.width - 1))
	local dy = math.max(b.tileY - y, 0, y - (b.tileY + b.depth - 1))
	return math.max(dx, dy)
end

-- The facilities nearest tile (x, y) first; ties keep pool order.
local function nearestFirst(ctx, x, y)
	local list = StorageFacility.all(ctx)
	local order = {}
	for i, b in ipairs(list) do
		order[b] = i
	end
	table.sort(list, function(a, b)
		local da, db = distance(a, x, y), distance(b, x, y)
		if da ~= db then
			return da < db
		end
		return order[a] < order[b]
	end)
	return list
end

-- Claims `cost` in the facilities for a construction site, the one
-- nearest tile (x, y) first, spilling to the next when it runs short; items
-- in name order, each facility's storage before its port buffers. Check
-- StorageFacility.has first. Returns the claims, in that order:
--   { building = <facility>, store = <Storage>, item, count, taking = 0 }
-- (`taking`: how many haul jobs are on their way to pick up.)
function StorageFacility.claim(ctx, cost, x, y)
	assert(StorageFacility.has(ctx, cost), "storage can't cover the cost")
	local items = {}
	for item in pairs(cost) do
		items[#items + 1] = item
	end
	table.sort(items)
	local claims = {}
	local facilities = nearestFirst(ctx, x, y)
	for _, item in ipairs(items) do
		local n = cost[item]
		for _, b in ipairs(facilities) do
			for _, store in ipairs(stores(b)) do
				local take = math.min(n, Storage.unclaimed(store, item))
				if take > 0 then
					Storage.claim(store, item, take)
					claims[#claims + 1] = { building = b, store = store, item = item, count = take, taking = 0 }
					n = n - take
				end
			end
		end
	end
	return claims
end

return StorageFacility
