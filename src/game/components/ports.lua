-- Port buffers (docs/CONTEXT.md "Port", "Buffer") and where a building's
-- products go: storage first, then the output buffers in port order.
-- Storage drains into output buffers as they free up (Ports.flush), so the
-- player collects everything at the output port tiles. Pure -- no `love.*`.
local Storage = require("src.game.components.storage")
local Inventory = require("src.game.components.inventory")

local Ports = {}

-- Gives every port of `ports` an empty buffer sized by the capacity trait.
function Ports.setup(ports, traits, config)
	local size = Storage.size(config.production.bufferSize, traits, config)
	for _, port in ipairs(ports) do
		port.buffer = Storage.new(size)
	end
end

-- Whether `building` holds fewer products than it can (storage or an
-- output). Counts what is stored, not room reserved by jobs on their way
-- (Storage.reserveRoom), so a building is not shown FULL while an
-- operator is still walking a load to its output.
function Ports.hasRoom(building)
	local function free(store)
		return store.capacity - Storage.total(store) > 0
	end
	if free(building.storage) then
		return true
	end
	for _, port in ipairs(building.ports) do
		if port.kind == "output" and free(port.buffer) then
			return true
		end
	end
	return false
end

-- Puts one `item` into storage, else the first output buffer with room.
-- Check Ports.hasRoom first.
function Ports.push(building, item)
	if Storage.room(building.storage) > 0 then
		Storage.add(building.storage, item)
		return
	end
	for _, port in ipairs(building.ports) do
		if port.kind == "output" and Storage.room(port.buffer) > 0 then
			Storage.add(port.buffer, item)
			return
		end
	end
	error("building has no room")
end

-- Moves stored items into output buffers with room, in port order, items
-- in name order. Items a haul job reserved in storage stay for it.
function Ports.flush(building)
	local storage = building.storage
	for _, port in ipairs(building.ports) do
		if port.kind == "output" then
			for _, item in ipairs(Storage.items(storage)) do
				while Storage.available(storage, item) > 0 and Storage.room(port.buffer) > 0 do
					Storage.remove(storage, item)
					Storage.add(port.buffer, item)
				end
			end
		end
	end
end

-- Whether `building` takes `item` at its input ports: a depot takes every
-- item, otherwise some converting function brick must consume it.
function Ports.accepts(building, item)
	for _, fb in ipairs(building.functionBricks) do
		if fb.depot or (fb.recipe and fb.recipe.input[item]) then
			return true
		end
	end
	return false
end

-- Moves accepted items from `inventory` into input `port`'s buffer, up to
-- its free space; other items stay with the player.
function Ports.deliver(port, building, inventory)
	local items = {}
	for item in pairs(inventory.counts) do
		table.insert(items, item)
	end
	table.sort(items)
	for _, item in ipairs(items) do
		if Ports.accepts(building, item) then
			local n = math.min(Inventory.count(inventory, item), Storage.room(port.buffer))
			for _ = 1, n do
				Storage.add(port.buffer, item)
			end
			if n > 0 then
				Inventory.spend(inventory, { [item] = n })
			end
		end
	end
end

-- Empties `port`'s buffer into `inventory`, all but what a construction
-- site claimed.
function Ports.collect(port, inventory)
	local buffer = port.buffer
	for _, item in ipairs(Storage.items(buffer)) do
		local n = Storage.unclaimed(buffer, item)
		if n > 0 then
			Inventory.add(inventory, item, n)
			local left = buffer.counts[item] - n
			buffer.counts[item] = left > 0 and left or nil
		end
	end
end

return Ports
