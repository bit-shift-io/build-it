-- A bounded item store (docs/CONTEXT.md "Storage brick", "Buffer"): plain
-- data `{ counts = { [item] = n }, capacity = <items> }`. A building's
-- storage and each port's buffer are one of these; capacity counts every
-- item together. Pure -- no `love.*`.
local Storage = {}

function Storage.new(capacity)
	return { counts = {}, capacity = capacity }
end

-- `base` items grown by the capacity trait (config.production.capacityStep
-- per point), rounded down, never below 0.
function Storage.size(base, traits, config)
	local grown = base * (1 + traits.capacity * config.production.capacityStep)
	return math.max(0, math.floor(grown + 1e-9))
end

-- A building's internal storage: the sum of its storage bricks' `storage`,
-- grown by its capacity trait. 0 when it has no storage brick.
function Storage.ofVersion(version, traits, config)
	local base = 0
	for _, b in ipairs(version.bricks) do
		base = base + (b.storage or 0)
	end
	return Storage.new(Storage.size(base, traits, config))
end

function Storage.total(store)
	local n = 0
	for _, count in pairs(store.counts) do
		n = n + count
	end
	return n
end

function Storage.room(store)
	return store.capacity - Storage.total(store)
end

-- Adds one `item`. Check Storage.room first.
function Storage.add(store, item)
	assert(Storage.room(store) > 0, "store is full")
	store.counts[item] = (store.counts[item] or 0) + 1
end

-- Takes one `item` out. Check it is there first.
function Storage.remove(store, item)
	assert((store.counts[item] or 0) > 0, "no " .. tostring(item) .. " to take")
	store.counts[item] = store.counts[item] - 1
	if store.counts[item] == 0 then
		store.counts[item] = nil
	end
end

-- The items in `store`, in name order (deterministic, unlike pairs).
function Storage.items(store)
	local items = {}
	for item in pairs(store.counts) do
		table.insert(items, item)
	end
	table.sort(items)
	return items
end

return Storage
