-- A building record (docs/CONTEXT.md "Building"): a placed design version,
-- in ctx.pools.buildings. Plain data, pure -- no `love.*`.
--
--   { id, design = <library design>, version = <n>, facing,
--     tileX, tileY,           -- the footprint's north-west tile
--     width, depth,           -- the footprint in tiles, turned by facing
--     ports = { <port>, ... } }
--   port = { kind = "input"|"output", side, x, y, -- the tile it faces
--            buffer = { counts = { [item] = n } } }
--
-- A version is immutable, so design.versions[version] stays the plan this
-- building was built from however the design is edited later.
local Building = {}

-- ports: Placement.ports's list; each gets an empty buffer.
function Building.new(id, request, width, depth, ports)
	for _, port in ipairs(ports) do
		port.buffer = { counts = {} }
	end
	return {
		id = id,
		design = request.design,
		version = request.version,
		facing = request.facing,
		tileX = request.tileX,
		tileY = request.tileY,
		width = width,
		depth = depth,
		ports = ports,
	}
end

return Building
