-- Harvestable component: the rules for taking items out of a resource node
-- (a tree or rock record, docs/CONTEXT.md "Resource node"). The node holds
-- its own `amount` and `stage`; a harvester holds `{ progress = <seconds> }`.
-- Called by CharacterSystem; never runs itself. Removal of a dead node is
-- NodeSystem's sweep, not done here.
local Inventory = require("src.game.components.inventory")

local Harvestable = {}

function Harvestable.canHarvest(node)
	return node.amount > 0 and not node.dead and not node.growing
end

-- The stage for `amount` left of `max`: one past each stageAt threshold the
-- remaining fraction has reached.
local function stageFor(def, amount, max)
	local stage = 1
	for _, at in ipairs(def.stageAt) do
		if amount / max <= at then
			stage = stage + 1
		end
	end
	return stage
end

-- Takes one item out of the node: lowers amount, steps the stage, marks a
-- depleted node dead. Returns the item name. Check canHarvest first.
function Harvestable.take(node, config)
	local def = config.nodes[node.kind]
	node.amount = node.amount - 1
	node.stage = stageFor(def, node.amount, def.amount)
	if node.amount <= 0 then
		node.dead = true
	end
	return def.item
end

-- Advances `dt` seconds of work on the node. Each config.harvest.handCycle
-- of work moves one item into `inventory`.
function Harvestable.work(harvester, node, dt, inventory, config)
	harvester.progress = harvester.progress + dt
	while harvester.progress >= config.harvest.handCycle do
		harvester.progress = harvester.progress - config.harvest.handCycle
		if not Harvestable.canHarvest(node) then
			harvester.progress = 0
			return
		end
		Inventory.add(inventory, Harvestable.take(node, config), 1)
	end
end

return Harvestable
