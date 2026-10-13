-- Placing a design version in the world as a building (docs/CONTEXT.md
-- "Building", "Footprint", "Facing", "Port"). Pure -- no `love.*`.
--
-- Turns match the baker's (Model.rotate): each facing after N turns the
-- design a quarter clockwise seen from above, tile (x, y) of a w x d
-- footprint going to (d - 1 - y, x).
local World = require("src.game.world")
local Building = require("src.game.buildings.building")
local Cost = require("src.game.builder.cost")
local Inventory = require("src.game.components.inventory")

local Placement = {}

local QUARTER_TURNS = { N = 0, E = 1, S = 2, W = 3 }

local function turns(facing)
	return assert(QUARTER_TURNS[facing], "unknown facing " .. tostring(facing))
end

-- The footprint of `version` turned to `facing`: width, depth in tiles.
function Placement.footprint(version, facing)
	if turns(facing) % 2 == 1 then
		return version.depth, version.width
	end
	return version.width, version.depth
end

local CLOCKWISE = { N = "E", E = "S", S = "W", W = "N" }
local STEP = { N = { 0, -1 }, E = { 1, 0 }, S = { 0, 1 }, W = { -1, 0 } }

-- The footprint edge a ground-level brick touches, or nil. A brick in a
-- corner touches two edges; the north or south one wins.
local function edgeOf(b, widthStuds, depthStuds)
	if b.y == 0 then
		return "N"
	elseif b.y + b.depth == depthStuds then
		return "S"
	elseif b.x == 0 then
		return "W"
	elseif b.x + b.width == widthStuds then
		return "E"
	end
	return nil
end

-- The ports of `version` turned to `facing`, with its footprint's
-- north-west tile on world tile (tileX, tileY), in brick order:
--   { kind = "input"|"output", side = <facing of the edge>, x, y }
-- A port is a brick carrying `port` ("input" or "output") at ground level
-- (z = 0) on the footprint edge. It faces the tile just outside that edge,
-- beside the footprint tile under the brick's centre. cfg is
-- config.builder.
function Placement.ports(version, facing, tileX, tileY, cfg)
	local studs = cfg.studsPerTile
	local ports = {}
	for _, b in ipairs(version.bricks) do
		local side = b.port and b.z == 0 and edgeOf(b, version.width * studs, version.depth * studs)
		if side then
			local x = math.floor((b.x + b.width / 2) / studs)
			local y = math.floor((b.y + b.depth / 2) / studs)
			local width, depth = version.width, version.depth
			for _ = 1, turns(facing) do
				x, y = depth - 1 - y, x
				width, depth = depth, width
				side = CLOCKWISE[side]
			end
			local step = STEP[side]
			table.insert(ports, { kind = b.port, side = side, x = tileX + x + step[1], y = tileY + y + step[2] })
		end
	end
	return ports
end

-- request = { design = <library design>, version = <n>, facing, tileX, tileY }
local function plan(request)
	return assert(request.design.versions[request.version], "no such design version")
end

local function inWorld(world, x, y)
	return x >= 0 and y >= 0 and x < world.width and y < world.height
end

-- Why a building may not stand on tile (x, y), or nil when it may.
local function tileProblem(world, x, y)
	if not inWorld(world, x, y) then
		return "outside"
	elseif World.terrainAt(world, x, y) == "water" then
		return "water"
	elseif World.nodeAt(world, x, y) then
		return "node"
	elseif World.buildingAt(world, x, y) then
		return "building"
	end
	return nil
end

-- Whether `request` may be placed, paying from `inventory`: true, or false
-- and why, checked in this order: a footprint tile is "outside" the world,
-- on "water", under a "node" or under a "building"; a port tile is off the
-- world or not open ("port blocked"); the cost is "unaffordable".
function Placement.check(ctx, request, inventory)
	local version = plan(request)
	local world = ctx.world
	local width, depth = Placement.footprint(version, request.facing)
	for y = request.tileY, request.tileY + depth - 1 do
		for x = request.tileX, request.tileX + width - 1 do
			local problem = tileProblem(world, x, y)
			if problem then
				return false, problem
			end
		end
	end
	for _, port in ipairs(Placement.ports(version, request.facing, request.tileX, request.tileY, ctx.config.builder)) do
		if tileProblem(world, port.x, port.y) then
			return false, "port blocked"
		end
	end
	if not Inventory.has(inventory, Cost.of(version, ctx.config)) then
		return false, "unaffordable"
	end
	return true
end

-- Places `request` for `character`, paying from its inventory: a new
-- building in ctx.pools.buildings, its tiles marked in the world. Returns
-- the building, or nil and why (Placement.check) when refused.
function Placement.place(ctx, character, request)
	local ok, reason = Placement.check(ctx, request, character.inventory)
	if not ok then
		return nil, reason
	end
	local version = plan(request)
	local width, depth = Placement.footprint(version, request.facing)
	local ports = Placement.ports(version, request.facing, request.tileX, request.tileY, ctx.config.builder)
	Inventory.spend(character.inventory, Cost.of(version, ctx.config))
	local pool = ctx.pools.buildings
	local building = Building.new(#pool + 1, request, width, depth, ports)
	table.insert(pool, building)
	World.addBuilding(ctx.world, building)
	return building
end

return Placement
