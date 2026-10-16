-- A building record (docs/CONTEXT.md "Building"): a placed design version,
-- in ctx.pools.buildings. Plain data, pure -- no `love.*`.
--
--   { id, design = <library design>, version = <n>, facing,
--     tileX, tileY,           -- the footprint's north-west tile
--     width, depth,           -- the footprint in tiles, turned by facing
--     traits,                 -- Traits.of(the version)
--     aura,                   -- Traits.auras(the version): { walkSpeed, harvestRate }
--     functionBricks = { <function brick>, ... }, -- function_brick.lua;
--                             -- each with tileX, tileY: its brick's tile
--     storage,                -- a Storage (src/game/components/storage.lua)
--     full,                   -- true while it has no room for a product
--     ports = { <port>, ... } }
--   port = { kind = "input"|"output", side, x, y, -- the tile it faces
--            buffer = <Storage> }
--
-- A version is immutable, so design.versions[version] stays the plan this
-- building was built from however the design is edited later.
local Traits = require("src.game.builder.traits")
local FunctionBrick = require("src.game.components.function_brick")
local Storage = require("src.game.components.storage")
local Ports = require("src.game.components.ports")

local Building = {}

-- ports: Placement.ports's list; each gets an empty buffer sized by the
-- version's capacity trait. brickTile(brick) -> x, y: the world tile under
-- a brick (Placement.brickTile), set on each function brick record.
function Building.new(id, request, width, depth, ports, config, brickTile)
	local version = request.design.versions[request.version]
	local traits = Traits.of(version, config)
	Ports.setup(ports, traits, config)
	local building = {
		id = id,
		design = request.design,
		version = request.version,
		facing = request.facing,
		tileX = request.tileX,
		tileY = request.tileY,
		width = width,
		depth = depth,
		traits = traits,
		aura = Traits.auras(version, config),
		functionBricks = FunctionBrick.fromVersion(version, config, brickTile),
		storage = Storage.ofVersion(version, traits, config),
		full = false,
		ports = ports,
	}
	for _, port in ipairs(ports) do
		port.building = building -- so a port tile reaches its building
	end
	return building
end

return Building
