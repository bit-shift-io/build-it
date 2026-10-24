-- A building record (docs/CONTEXT.md "Building"): a placed blueprint, in
-- ctx.pools.buildings. Plain data, pure -- no `love.*`.
--
--   { id, design,           -- the design's name, a label only
--     blueprint,              -- frozen at placement (blueprint.lua)
--     facing,
--     tileX, tileY,           -- the footprint's north-west tile
--     width, depth,           -- the footprint in tiles, turned by facing
--     traits,                 -- the blueprint's traits
--     aura,                   -- the blueprint's auras: { walkSpeed, harvestRate }
--     functionBricks = { <function brick>, ... }, -- function_brick.lua;
--                             -- each with tileX, tileY: its role's tile,
--                             -- and pointX, pointY: its role's position
--     storage,                -- a Storage (src/game/components/storage.lua)
--     full,                   -- true while it has no room for a product
--     ports = { <port>, ... } }
--   port = { kind = "input"|"output", side, x, y, -- the tile it faces
--            buffer = <Storage> }
--
-- A blueprint is never changed, so it stays the plan this building was
-- built from however its design is edited later (ADR 0007).
local FunctionBrick = require("src.game.components.function_brick")
local Storage = require("src.game.components.storage")
local Ports = require("src.game.components.ports")

local Building = {}

local function copy(t)
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	return out
end

-- ports: Placement.ports's list; each gets an empty buffer sized by the
-- capacity trait. roleTile(role) -> x, y, px, py: the world tile under a
-- role position and that position (Placement.roleTile), set on each
-- function brick record.
function Building.new(id, request, blueprint, width, depth, ports, config, roleTile)
	local traits = copy(blueprint.traits)
	Ports.setup(ports, traits, config)
	local building = {
		id = id,
		design = request.design,
		blueprint = blueprint,
		facing = request.facing,
		tileX = request.tileX,
		tileY = request.tileY,
		width = width,
		depth = depth,
		traits = traits,
		aura = copy(blueprint.auras),
		functionBricks = FunctionBrick.fromBlueprint(blueprint, config, roleTile),
		storage = Storage.ofBlueprint(blueprint, traits, config),
		full = false,
		ports = ports,
	}
	for _, port in ipairs(ports) do
		port.building = building -- so a port tile reaches its building
	end
	return building
end

return Building
