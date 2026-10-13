-- Inventory component: the items a record carries, unlimited
-- (docs/CONTEXT.md "Inventory"). Plain data on the record
-- (`record.inventory = { counts = { [item] = n } }`).
local Inventory = {}

-- stockpile: { [item] = n } to start with (config.stockpile), or nil.
function Inventory.new(stockpile)
	local counts = {}
	for item, n in pairs(stockpile or {}) do
		counts[item] = n
	end
	return { counts = counts }
end

function Inventory.count(inv, item)
	return inv.counts[item] or 0
end

function Inventory.add(inv, item, n)
	inv.counts[item] = (inv.counts[item] or 0) + (n or 1)
end

return Inventory
