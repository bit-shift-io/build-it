-- A blueprint (docs/CONTEXT.md "Blueprint", ADR 0007): a design compiled
-- for placing, frozen into its site or building. The simulation reads only
-- blueprints. Plain data, never changed once made; pure -- no `love.*`.
--
--   { width, depth,          -- the footprint in tiles, unturned
--     mesh,                  -- the geometry: a triangle list in tiles
--                            -- (src/game/geometry/primitives.lua's vertices)
--     roles = {
--       abilities = { { ability, x, y }, ... }, -- function bricks
--       ports = { { kind = "input"|"output", edge = "N"|"E"|"S"|"W", x, y }, ... },
--       storage = <items>,   -- base storage, before the capacity trait
--     },
--     cost = { [item] = n },
--     traits,                -- { productivity, capacity, reach, health }
--     auras,                 -- { walkSpeed, harvestRate }
--     walk,                  -- the walk grid, unturned: { width, depth,
--                            -- cells } in stud cells
--                            -- (src/game/buildings/walk_grid.lua)
--     hash }                 -- Blueprint.hash: the content hash
--
-- Role positions are model space in tile fractions, before any facing:
-- (0, 0) the footprint's north-west corner, x east, y south.
local bit = require("bit")

local Blueprint = {}

-- `value` as text that depends only on its content: table keys sorted,
-- numbers exact.
local function canonical(value, out)
	local kind = type(value)
	if kind == "table" then
		local keys = {}
		for k in pairs(value) do
			keys[#keys + 1] = k
		end
		table.sort(keys, function(a, b)
			if type(a) ~= type(b) then
				return type(a) < type(b)
			end
			return a < b
		end)
		out[#out + 1] = "{"
		for _, k in ipairs(keys) do
			canonical(k, out)
			out[#out + 1] = "="
			canonical(value[k], out)
			out[#out + 1] = ";"
		end
		out[#out + 1] = "}"
	elseif kind == "number" then
		out[#out + 1] = string.format("%.17g", value)
	elseif kind == "string" then
		out[#out + 1] = string.format("%q", value)
	else
		out[#out + 1] = tostring(value)
	end
	return out
end

-- 32-bit FNV-1a of `text`, starting from `basis`, as 8 hex digits.
local function fnv1a(text, basis)
	local h = basis
	for i = 1, #text do
		h = bit.bxor(h, text:byte(i))
		h = bit.tobit(h * 16777619)
	end
	return bit.tohex(h, 8)
end

-- The content hash of `blueprint`: 16 hex digits over everything but its
-- `hash`, so equal content gives an equal hash whatever the tables.
function Blueprint.hash(blueprint)
	local content = {}
	for k, v in pairs(blueprint) do
		if k ~= "hash" then
			content[k] = v
		end
	end
	local text = table.concat(canonical(content, {}))
	return fnv1a(text, bit.tobit(2166136261)) .. fnv1a(text, bit.tobit(0x6c62272e))
end

return Blueprint
