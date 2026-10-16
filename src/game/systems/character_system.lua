-- Pool system for ctx.pools.characters. Calls each record's components
-- explicitly, in a visible order (docs/ARCHITECTURE.md "Systems and frame
-- order").
local Mover = require("src.game.components.mover")
local Harvestable = require("src.game.components.harvestable")
local Animator = require("src.game.components.animator")
local World = require("src.game.world")
local Ports = require("src.game.components.ports")
local Aura = require("src.game.components.aura")

local CharacterSystem = {}

local NO_INTENT = { x = 0, y = 0 }

-- Distance in px from (x, y) to the nearest point of tile (tx, ty).
local function distanceToTile(x, y, tx, ty, tile)
	local nx = math.max(tx * tile, math.min(x, (tx + 1) * tile))
	local ny = math.max(ty * tile, math.min(y, (ty + 1) * tile))
	return math.sqrt((x - nx) ^ 2 + (y - ny) ^ 2)
end

-- The harvestable node the character works on: the node on intent.target
-- (a tile) when given, else the nearest one; nil when none is within reach.
local function harvestTarget(c, intent, ctx)
	local tile, reach = ctx.config.tileSize, ctx.config.harvest.reach
	local function inReach(n)
		return n and Harvestable.canHarvest(n) and distanceToTile(c.x, c.y, n.tileX, n.tileY, tile) <= reach
	end
	if intent.target then
		local n = World.nodeAt(ctx.world, intent.target.x, intent.target.y)
		return inReach(n) and n or nil
	end
	local best, bestD
	local cx, cy = math.floor(c.x / tile), math.floor(c.y / tile)
	for ty = cy - 2, cy + 2 do
		for tx = cx - 2, cx + 2 do
			local n = World.nodeAt(ctx.world, tx, ty)
			if inReach(n) then
				local d = distanceToTile(c.x, c.y, tx, ty, tile)
				if not bestD or d < bestD then
					best, bestD = n, d
				end
			end
		end
	end
	return best
end

-- The output port whose tile character `c` stands on, or nil.
function CharacterSystem.outputPortUnder(c, ctx)
	local tile = ctx.config.tileSize
	local port = World.portAt(ctx.world, math.floor(c.x / tile), math.floor(c.y / tile))
	return port and port.kind == "output" and port or nil
end

-- The port (either kind) whose tile character `c` stands on, or nil.
local function portUnder(c, ctx)
	local tile = ctx.config.tileSize
	return World.portAt(ctx.world, math.floor(c.x / tile), math.floor(c.y / tile))
end

-- While intent.harvest is set: on an output port tile, collects its buffer;
-- on an input port tile, delivers what the building consumes;
-- elsewhere hand-harvests, progress resetting when the work stops or the
-- target changes.
local function harvest(c, intent, ctx, aura)
	local port = intent.harvest and portUnder(c, ctx)
	if port and port.kind == "output" then
		Ports.collect(port, c.inventory)
	elseif port and port.kind == "input" then
		Ports.deliver(port, port.building, c.inventory)
	else
		port = nil
	end
	local node = intent.harvest and not port and harvestTarget(c, intent, ctx)
	if not node then
		c.harvester.progress = 0
		c.harvester.node = nil
		return
	end
	if c.harvester.node ~= node then
		c.harvester.progress = 0
		c.harvester.node = node
	end
	Harvestable.work(c.harvester, node, ctx.dt * (1 + aura.harvestRate), c.inventory, ctx.config)
end

function CharacterSystem.update(ctx)
	for _, c in ipairs(ctx.pools.characters) do
		local intent = ctx.intents[c.player] or NO_INTENT
		local fromX, fromY = c.x, c.y
		local aura = Aura.at(ctx, c)
		local baseSpeed = c.mover.speed
		c.mover.speed = baseSpeed * (1 + aura.walkSpeed)
		Mover.apply(c, intent, ctx)
		c.mover.speed = baseSpeed
		Animator.update(c.animator, c.x - fromX, c.y - fromY, ctx.config.character)
		harvest(c, intent, ctx, aura)
	end
end

return CharacterSystem
