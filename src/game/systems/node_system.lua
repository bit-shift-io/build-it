-- Pool system for ctx.pools.nodes: node reservations and the despawn sweep.
--
-- Reservations: a function brick (src/game/components/function_brick.lua)
-- holds at most one node and a node is held by at most one brick:
-- node.reservedBy = brick, brick.node = node. Hand harvesting ignores them.
--
-- Despawn: removes nodes marked dead (depleted). The only place nodes leave
-- the pool. ctx.pools.nodes is the world's node pool, so removal goes
-- through World.removeNode to clear the tile too.
local World = require("src.game.world")

-- Tree prop stages 4 and 5 (src/game/props/tree.lua): sapling, young.
local SAPLING = 4

local NodeSystem = {}

-- A sapling (node.growing) is not free: nothing may reserve it until grown.
function NodeSystem.isFree(node)
	return node.reservedBy == nil and node.growing == nil
end

-- Reserves `node` for `holder` (a record with a `node` field).
function NodeSystem.reserve(node, holder)
	assert(NodeSystem.isFree(node), "node already reserved")
	node.reservedBy = holder
	holder.node = node
end

-- Frees `node` and clears its holder's hold on it.
function NodeSystem.release(node)
	if node.reservedBy then
		node.reservedBy.node = nil
	end
	node.reservedBy = nil
end

-- Plants a sapling of `kind` on tile (x, y), which the caller has checked is
-- free. Ids come from ctx.nextNodeId, so they never repeat after a removal.
-- The variant comes from ctx.rng.
function NodeSystem.plant(ctx, kind, x, y)
	if not ctx.nextNodeId then
		local top = 0
		for _, n in ipairs(ctx.pools.nodes) do
			top = math.max(top, n.id)
		end
		ctx.nextNodeId = top + 1
	end
	local node = {
		id = ctx.nextNodeId,
		kind = kind,
		tileX = x,
		tileY = y,
		variant = ctx.rng:int(1, ctx.config.props.variants),
		stage = SAPLING,
		amount = ctx.config.nodes[kind].amount,
		growing = 0,
	}
	ctx.nextNodeId = ctx.nextNodeId + 1
	return World.addNode(ctx.world, node)
end

-- Grows saplings: node.growing counts seconds; the first half of
-- nodes.<kind>.growTime is the sapling stage, the second the young stage,
-- then the node is a full stage-1 node and harvestable.
function NodeSystem.grow(ctx)
	for _, n in ipairs(ctx.pools.nodes) do
		if n.growing then
			n.growing = n.growing + ctx.dt
			local time = ctx.config.nodes[n.kind].growTime
			if n.growing >= time then
				n.growing = nil
				n.stage = 1
			elseif n.growing >= time / 2 then
				n.stage = SAPLING + 1
			end
		end
	end
end

-- Releases the reservations of dead nodes. Runs before function bricks pick
-- targets, so none keeps working a node the sweep is about to remove.
function NodeSystem.releaseDead(ctx)
	for _, n in ipairs(ctx.pools.nodes) do
		if n.dead then
			NodeSystem.release(n)
		end
	end
end

function NodeSystem.despawn(ctx)
	local dead = {}
	for _, n in ipairs(ctx.pools.nodes) do
		if n.dead then
			table.insert(dead, n)
		end
	end
	for _, n in ipairs(dead) do
		World.removeNode(ctx.world, n)
	end
end

return NodeSystem
