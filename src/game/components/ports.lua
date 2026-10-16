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

-- Whether `building` can take one more product (storage or an output).
function Ports.hasRoom(building)
	if Storage.room(building.storage) > 0 then
		return true
	end
	for _, port in ipairs(building.ports) do
		if port.kind == "output" and Storage.room(port.buffer) > 0 then
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
-- in name order.
function Ports.flush(building)
	local storage = building.storage
	for _, port in ipairs(building.ports) do
		if port.kind == "output" then
			for _, item in ipairs(Storage.items(storage)) do
				while storage.counts[item] and Storage.room(port.buffer) > 0 do
					Storage.remove(storage, item)
					Storage.add(port.buffer, item)
				end
			end
		end
	end
end

-- Whether some converting function brick of `building` consumes `item`.
function Ports.accepts(building, item)
	for _, fb in ipairs(building.functionBricks) do
		if fb.recipe and fb.recipe.input[item] then
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

local function available(building, item)
	local n = building.storage.counts[item] or 0
	for _, port in ipairs(building.ports) do
		if port.kind == "input" then
			n = n + (port.buffer.counts[item] or 0)
		end
	end
	return n
end

-- Whether input buffers and storage together hold every item of `cost`.
function Ports.canPull(building, cost)
	for item, n in pairs(cost) do
		if available(building, item) < n then
			return false
		end
	end
	return true
end

-- Takes `cost` from input buffers (port order), then storage. Check
-- Ports.canPull first.
function Ports.pull(building, cost)
	for item, n in pairs(cost) do
		for _, store in ipairs(Ports.sources(building)) do
			while n > 0 and (store.counts[item] or 0) > 0 do
				Storage.remove(store, item)
				n = n - 1
			end
		end
	end
end

function Ports.sources(building)
	local list = {}
	for _, port in ipairs(building.ports) do
		if port.kind == "input" then
			table.insert(list, port.buffer)
		end
	end
	table.insert(list, building.storage)
	return list
end

-- Empties `port`'s buffer into `inventory`.
function Ports.collect(port, inventory)
	for _, item in ipairs(Storage.items(port.buffer)) do
		Inventory.add(inventory, item, port.buffer.counts[item])
		port.buffer.counts[item] = nil
	end
end

return Ports
