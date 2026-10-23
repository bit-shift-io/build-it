-- Placing a design's blueprint in the world as a building (docs/CONTEXT.md
-- "Building", "Blueprint", "Footprint", "Facing", "Port"). Pure -- no
-- `love.*`. Reads only blueprints (src/game/buildings/blueprint.lua).
--
-- Turns match the baked sprites' (Mesh.turn): each facing after N turns the
-- design a quarter clockwise seen from above, tile (x, y) of a w x d
-- footprint going to (d - 1 - y, x).
local World = require("src.game.world")
local Building = require("src.game.buildings.building")
local StorageFacility = require("src.game.components.storage_facility")
local Site = require("src.game.buildings.site")

local Placement = {}

local QUARTER_TURNS = { N = 0, E = 1, S = 2, W = 3 }

local function turns(facing)
	return assert(QUARTER_TURNS[facing], "unknown facing " .. tostring(facing))
end

-- The 4 facings in clockwise order (docs/CONTEXT.md "Facing"): N is the
-- design as authored, each next one a quarter turn clockwise from above.
Placement.FACINGS = { "N", "E", "S", "W" }

-- request = { design = <design name>, blueprint, facing, tileX, tileY }:
-- what to place, its blueprint (src/game/buildings/compile.lua's, frozen
-- into the site or building) and where. Its blueprint.
function Placement.blueprint(request)
	return assert(request.blueprint, "a placement request needs a blueprint")
end

-- The footprint of `blueprint` turned to `facing`: width, depth in tiles.
function Placement.footprint(blueprint, facing)
	if turns(facing) % 2 == 1 then
		return blueprint.depth, blueprint.width
	end
	return blueprint.width, blueprint.depth
end

local CLOCKWISE = { N = "E", E = "S", S = "W", W = "N" }
local STEP = { N = { 0, -1 }, E = { 1, 0 }, S = { 0, 1 }, W = { -1, 0 } }

-- The world tile under role position `role` ({ x, y }, model space in tile
-- fractions) of `blueprint` turned to `facing` with its footprint's
-- north-west tile on (tileX, tileY): where a function brick's operator
-- stands, or the footprint tile behind a port.
function Placement.roleTile(blueprint, facing, tileX, tileY, role)
	local x, y = math.floor(role.x), math.floor(role.y)
	local width, depth = blueprint.width, blueprint.depth
	for _ = 1, turns(facing) do
		x, y = depth - 1 - y, x
		width, depth = depth, width
	end
	return tileX + x, tileY + y
end

-- The ports of `blueprint` turned to `facing`, with its footprint's
-- north-west tile on world tile (tileX, tileY), in role order:
--   { kind = "input"|"output", side = <facing of the edge>, x, y }
-- A port faces the tile just outside its edge, beside the footprint tile
-- under its position.
function Placement.ports(blueprint, facing, tileX, tileY)
	local ports = {}
	for _, role in ipairs(blueprint.roles.ports) do
		local x, y = Placement.roleTile(blueprint, facing, tileX, tileY, role)
		local side = role.edge
		for _ = 1, turns(facing) do
			side = CLOCKWISE[side]
		end
		local step = STEP[side]
		table.insert(ports, { kind = role.kind, side = side, x = x + step[1], y = y + step[2] })
	end
	return ports
end

-- A new building record for `request` (not yet in the pool or the world):
-- its footprint, ports and function brick tiles worked out from its
-- blueprint. Shared by Placement.build and the save codec.
function Placement.assemble(id, request, config)
	local blueprint = Placement.blueprint(request)
	local width, depth = Placement.footprint(blueprint, request.facing)
	local ports = Placement.ports(blueprint, request.facing, request.tileX, request.tileY)
	return Building.new(id, request, blueprint, width, depth, ports, config, function(role)
		return Placement.roleTile(blueprint, request.facing, request.tileX, request.tileY, role)
	end)
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
local function fits(ctx, request, blueprint)
	local world = ctx.world
	local width, depth = Placement.footprint(blueprint, request.facing)
	for y = request.tileY, request.tileY + depth - 1 do
		for x = request.tileX, request.tileX + width - 1 do
			local problem = tileProblem(world, x, y)
			if problem then
				return false, problem
			end
		end
	end
	for _, port in ipairs(Placement.ports(blueprint, request.facing, request.tileX, request.tileY)) do
		if tileProblem(world, port.x, port.y) then
			return false, "port blocked"
		end
	end
	return true
end

function Placement.fits(ctx, request)
	return fits(ctx, request, Placement.blueprint(request))
end

local function check(ctx, request, blueprint)
	local ok, reason = fits(ctx, request, blueprint)
	if not ok then
		return false, reason
	end
	if not StorageFacility.has(ctx, blueprint.cost) then
		return false, "unaffordable"
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
	return check(ctx, request, Placement.blueprint(request))
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
	local blueprint = Placement.blueprint(request)
	local ok, reason = check(ctx, request, blueprint)
	if not ok then
		return nil, reason
	end
	local cost = {}
	for item, n in pairs(blueprint.cost) do
		cost[item] = n
	end
	local claims = StorageFacility.claim(ctx, cost, request.tileX, request.tileY)
	local width, depth = Placement.footprint(blueprint, request.facing)
	local site = Site.new(request, blueprint, width, depth, cost, claims)
	table.insert(ctx.pools.sites, site)
	World.addBuilding(ctx.world, site)
	return site
end

return Placement
