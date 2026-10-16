-- Placing a design version in the world as a building (docs/CONTEXT.md
-- "Building", "Footprint", "Facing", "Port"). Pure -- no `love.*`.
--
-- Turns match the baker's (Model.rotate): each facing after N turns the
-- design a quarter clockwise seen from above, tile (x, y) of a w x d
-- footprint going to (d - 1 - y, x).
local World = require("src.game.world")
local Building = require("src.game.buildings.building")
local Cost = require("src.game.builder.cost")
local Bricks = require("src.game.builder.bricks")
local StorageFacility = require("src.game.components.storage_facility")
local Site = require("src.game.buildings.site")

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

-- The footprint tile under brick `b`'s centre, before turning.
local function centreTile(b, studs)
	return math.floor((b.x + b.width / 2) / studs), math.floor((b.y + b.depth / 2) / studs)
end

-- Footprint tile (x, y) of `version` turned to `facing`.
local function rotate(version, facing, x, y)
	local width, depth = version.width, version.depth
	for _ = 1, turns(facing) do
		x, y = depth - 1 - y, x
		width, depth = depth, width
	end
	return x, y
end

-- The world tile under brick `b`'s centre, for `version` turned to
-- `facing` with its footprint's north-west tile on (tileX, tileY): where
-- a function brick's operator stands. cfg is config.builder.
function Placement.brickTile(version, facing, tileX, tileY, b, cfg)
	local x, y = rotate(version, facing, centreTile(b, cfg.studsPerTile))
	return tileX + x, tileY + y
end

-- The ports of `version` turned to `facing`, with its footprint's
-- north-west tile on world tile (tileX, tileY), in brick order:
--   { kind = "input"|"output", side = <facing of the edge>, x, y }
-- A port is a brick carrying `port` ("input" or "output") at ground level
-- (z = 0) on the footprint edge (Bricks.edge, which also settles a corner
-- port's edge). It faces the tile just outside that edge,
-- beside the footprint tile under the brick's centre. cfg is
-- config.builder.
function Placement.ports(version, facing, tileX, tileY, cfg)
	local ports = {}
	for _, b in ipairs(version.bricks) do
		local side = b.port and Bricks.edge(b, version, cfg)
		if side then
			local x, y = Placement.brickTile(version, facing, tileX, tileY, b, cfg)
			for _ = 1, turns(facing) do
				side = CLOCKWISE[side]
			end
			local step = STEP[side]
			table.insert(ports, { kind = b.port, side = side, x = x + step[1], y = y + step[2] })
		end
	end
	return ports
end

-- A new building record for `request` (not yet in the pool or the world):
-- its footprint, ports and function brick tiles worked out from its
-- design version. Shared by Placement.build and the save codec.
function Placement.assemble(id, request, config)
	local version = assert(request.design.versions[request.version], "no such design version")
	local cfg = config.builder
	local width, depth = Placement.footprint(version, request.facing)
	local ports = Placement.ports(version, request.facing, request.tileX, request.tileY, cfg)
	return Building.new(id, request, width, depth, ports, config, function(b)
		return Placement.brickTile(version, request.facing, request.tileX, request.tileY, b, cfg)
	end)
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

-- Whether `request`'s footprint and port tiles are open: true, or false
-- and why ("outside", "water", "node", "building", "port blocked"), as
-- for Placement.check.
function Placement.fits(ctx, request)
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
	return true
end

-- Whether `request` may be placed, paying from the storage facilities
-- (src/game/components/storage_facility.lua): true, or false and why,
-- checked in this order: a footprint tile is "outside" the world, on
-- "water", under a "node" or under a "building"; a port tile is off the
-- world or not open ("port blocked"); storage can't cover the cost
-- ("unaffordable").
function Placement.check(ctx, request)
	local ok, reason = Placement.fits(ctx, request)
	if not ok then
		return false, reason
	end
	if not StorageFacility.has(ctx, Cost.of(plan(request), ctx.config)) then
		return false, "unaffordable"
	end
	return true
end

-- Puts `request` in the world without checking or paying: a new finished
-- building in ctx.pools.buildings, its tiles marked in the world. For the
-- free starting storage facility (Session.newGame) and a site once built
-- (BuildingSystem). Returns the building.
function Placement.build(ctx, request)
	local pool = ctx.pools.buildings
	local building = Placement.assemble(#pool + 1, request, ctx.config)
	table.insert(pool, building)
	World.addBuilding(ctx.world, building)
	return building
end

-- Places `request` as a construction site (src/game/buildings/site.lua)
-- in ctx.pools.sites, its footprint marked in the world, its cost claimed
-- in the storage facilities nearest its footprint first. Returns the site,
-- or nil and why (Placement.check) when refused.
function Placement.place(ctx, request)
	local ok, reason = Placement.check(ctx, request)
	if not ok then
		return nil, reason
	end
	local version = plan(request)
	local cost = Cost.of(version, ctx.config)
	local claims = StorageFacility.claim(ctx, cost, request.tileX, request.tileY)
	local width, depth = Placement.footprint(version, request.facing)
	local site = Site.new(request, width, depth, cost, claims)
	table.insert(ctx.pools.sites, site)
	World.addBuilding(ctx.world, site)
	return site
end

return Placement
