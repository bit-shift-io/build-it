-- Pool system for ctx.pools.characters. Calls each record's components
-- explicitly, in a visible order (docs/ARCHITECTURE.md "Systems and frame
-- order").
local Mover = require("src.game.components.mover")
local Harvestable = require("src.game.components.harvestable")
local Animator = require("src.game.components.animator")
local World = require("src.game.world")
local Ports = require("src.game.components.ports")
local Aura = require("src.game.components.aura")
local Needs = require("src.game.components.needs")
local Idle = require("src.game.components.idle")
local Inventory = require("src.game.components.inventory")
local Storage = require("src.game.components.storage")
local StorageFacility = require("src.game.components.storage_facility")
local Eat = require("src.game.jobs.eat")
local Character = require("src.game.props.character")

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

-- The tile next to character `c` in its facing (8 directions, diagonals
-- included): docs/CONTEXT.md "Faced tile".
function CharacterSystem.facedTile(c, ctx)
	local tile = ctx.config.tileSize
	local d = Character.DIRECTIONS[c.animator.facing]
	return math.floor(c.x / tile) + d.x, math.floor(c.y / tile) + d.y
end

-- The port (either kind) E works on: the one on the tile character `c`
-- stands on, else the one on its faced tile, else nil.
function CharacterSystem.portInUse(c, ctx)
	local tile = ctx.config.tileSize
	local under = World.portAt(ctx.world, math.floor(c.x / tile), math.floor(c.y / tile))
	if under then
		return under
	end
	return World.portAt(ctx.world, CharacterSystem.facedTile(c, ctx))
end

-- While intent.harvest is set: at an output port (underfoot, else faced),
-- collects its buffer; at an input port, delivers what the building consumes;
-- elsewhere fishes the faced water tile (unless a node was clicked) or
-- hand-harvests, progress resetting when the work stops or the
-- target changes.
local function harvest(c, intent, ctx, aura)
	local port = intent.harvest and CharacterSystem.portInUse(c, ctx)
	if port and port.kind == "output" then
		Ports.collect(port, c.inventory)
	elseif port and port.kind == "input" then
		Ports.deliver(port, port.building, c.inventory, ctx.config.food)
	else
		port = nil
	end
	if not intent.harvest or port then
		c.harvester.progress = 0
		c.harvester.node = nil
		return
	end
	local node, water
	if intent.target then
		node = harvestTarget(c, intent, ctx)
	else
		local fx, fy = CharacterSystem.facedTile(c, ctx)
		if World.terrainAt(ctx.world, fx, fy) == "water" then
			water = fx .. "," .. fy
		else
			node = harvestTarget(c, intent, ctx)
		end
	end
	local key = node or water
	if not key then
		c.harvester.progress = 0
		c.harvester.node = nil
		return
	end
	if c.harvester.node ~= key then
		c.harvester.progress = 0
		c.harvester.node = key
	end
	local dt = ctx.dt * (1 + aura.harvestRate)
	if node then
		Harvestable.work(c.harvester, node, dt, c.inventory, ctx.config)
		return
	end
	-- Water never runs out: one catch per hand cycle.
	local cycle = ctx.config.harvest.handCycle
	c.harvester.progress = c.harvester.progress + dt
	while c.harvester.progress >= cycle do
		c.harvester.progress = c.harvester.progress - cycle
		Inventory.add(c.inventory, ctx.config.production.fishers.fishing, 1)
	end
end

-- Whole tiles from (x, y) in px to the footprint of building `b`.
local function distanceToBuilding(x, y, b, tile)
	local tx, ty = math.floor(x / tile), math.floor(y / tile)
	local dx = math.max(b.tileX - tx, 0, tx - (b.tileX + b.width - 1))
	local dy = math.max(b.tileY - ty, 0, ty - (b.tileY + b.depth - 1))
	return math.max(dx, dy)
end

-- A meal for the player (docs/CONTEXT.md "Meal"): eats from the inventory
-- when it holds food, else from the nearest storage facility within
-- config.facilityReach tiles (its storage, then its port buffers).
local function eat(c, ctx)
	local cfg = ctx.config
	local function meal(count, take)
		for _, item in ipairs(Eat.plan(count, c.needs.hunger, cfg.food)) do
			take(item)
			c.needs.hunger = math.max(0, c.needs.hunger - cfg.food[item].fill)
		end
	end
	local inv = c.inventory
	meal(function(item)
		return Inventory.count(inv, item)
	end, function(item)
		inv.counts[item] = inv.counts[item] - 1
	end)
	local best, bestD
	for _, b in ipairs(StorageFacility.all(ctx)) do
		local d = distanceToBuilding(c.x, c.y, b, cfg.tileSize)
		if d <= cfg.facilityReach and (not bestD or d < bestD) then
			best, bestD = b, d
		end
	end
	for _, store in ipairs(best and StorageFacility.stores(best) or {}) do
		meal(function(item)
			return Storage.available(store, item)
		end, function(item)
			Storage.remove(store, item)
		end)
	end
end

-- A collapsed character gets up at the gather area of the storage facility
-- nearest it (a random standable tile, from ctx.rng) with full needs and
-- the inventory it had. With no facility it gets up where it fell.
local function respawn(c, ctx)
	local tile = ctx.config.tileSize
	local b = Idle.nearestFacility(ctx, math.floor(c.x / tile), math.floor(c.y / tile))
	local tiles = b and Idle.gatherTiles(ctx, b) or {}
	if #tiles > 0 then
		local t = tiles[ctx.rng:int(1, #tiles)]
		c.x, c.y = (t.x + 0.5) * tile, (t.y + 0.5) * tile
	end
	c.needs = Needs.new()
	c.harvester.progress = 0
	c.harvester.node = nil
end

function CharacterSystem.update(ctx)
	for _, c in ipairs(ctx.pools.characters) do
		Needs.tick(c.needs, ctx.dt, ctx.config.needs, c.player ~= nil)
		if Needs.collapsed(c.needs) then
			respawn(c, ctx)
		end
		local intent = ctx.intents[c.player] or NO_INTENT
		local fromX, fromY = c.x, c.y
		local aura = Aura.at(ctx, c)
		local baseSpeed = c.mover.speed
		c.mover.speed = baseSpeed * (1 + aura.walkSpeed)
		Mover.apply(c, intent, ctx)
		c.mover.speed = baseSpeed
		Animator.update(c.animator, c.x - fromX, c.y - fromY, ctx.config.character)
		harvest(c, intent, ctx, aura)
		if intent.eat then
			eat(c, ctx)
		end
	end
end

return CharacterSystem
