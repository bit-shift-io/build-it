-- Load component (docs/CONTEXT.md "Load"): the items a villager carries.
-- Plain data on the record (`record.load`), one item kind at a time,
-- capped by config.villagers.carryLimit. Not an inventory. Pure.
--   load = { item = <item> | nil, count = <n>, limit = <carry limit> }
local Load = {}

function Load.new(config)
	return { item = nil, count = 0, limit = config.villagers.carryLimit }
end

function Load.empty(load)
	return load.count == 0
end

-- How many more items the load takes.
function Load.room(load)
	return load.limit - load.count
end

-- Adds `n` of `item`. The load must be empty or hold `item`, with room.
function Load.add(load, item, n)
	assert(load.count == 0 or load.item == item, "a load holds one kind of item")
	assert(n <= Load.room(load), "over the carry limit")
	if n > 0 then
		load.item = item
		load.count = load.count + n
	end
end

-- Takes `n` items out; the last one empties the load.
function Load.remove(load, n)
	assert(n <= load.count, "the load holds fewer items")
	load.count = load.count - n
	if load.count == 0 then
		load.item = nil
	end
end

return Load
