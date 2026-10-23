-- Design scripts for tests, compiled through the real compiler
-- (src/game/buildings/compile.lua) with the built-in prefabs
-- (tests/support/builtins.lua), so placed buildings stand on real
-- blueprints. Runs under plain LuaJIT.
--
--   local MILL = Designs.floor(2, 1,
--       Designs.ability("sawbench", 1, 0.5),
--       Designs.port("input", 0.5, 1),
--       Designs.storage(8, 1.5, 0.5))
--   Placement.build(ctx, Designs.request(MILL, "N", 10, 10))
--
-- Positions are model space in tiles: x east, y south, (0, 0) the
-- footprint's north-west corner. A port snaps to the footprint edge
-- nearest its position.
local Compile = require("src.game.buildings.compile")
local Config = require("src.game.config")
local builtins = require("tests.support.builtins")

local Designs = {}

local function number(n)
	return string.format("%.17g", n)
end

local function at(x, y)
	return "transform = { move = { " .. number(x) .. ", " .. number(y) .. ", 0 } }"
end

-- A role node's script text: an ability at (x, y).
function Designs.ability(ability, x, y)
	return string.format('role{ ability = %q, %s }', ability, at(x, y))
end

-- A role node's script text: a port of `kind` ("input" | "output") at
-- (x, y), snapping to the nearest footprint edge.
function Designs.port(kind, x, y)
	return string.format('role{ port = %q, %s }', kind, at(x, y))
end

-- A role node's script text: storage for `items` at (x, y).
function Designs.storage(items, x, y)
	return string.format("role{ storage = %d, %s }", items, at(x, y))
end

-- A design script: a plank floor `w` x `d` tiles and one voxel thick
-- (16 x 16 voxels a tile, so a trait point per tile), and further nodes
-- (roles, boxes) given as script text.
function Designs.floor(w, d, ...)
	local parts = { "box{ size = { " .. number(w) .. ", " .. number(d) .. ", 0.0625 } }" }
	for _, role in ipairs({ ... }) do
		parts[#parts + 1] = role
	end
	return "return group{ " .. table.concat(parts, ", ") .. " }"
end

-- Blueprints compiled so far, by config and script text: a blueprint never
-- changes, so tests may share one.
local made = setmetatable({}, { __mode = "k" })

-- The blueprint of design script `text`, tuned by `config` (default the
-- tuning table); raises when it doesn't compile.
function Designs.blueprint(text, config)
	config = config or Config
	made[config] = made[config] or {}
	local bp = made[config][text]
	if not bp then
		bp = assert(Compile.design(text, "test", builtins, config))
		made[config][text] = bp
	end
	return bp
end

-- A placement request (src/game/buildings/placement.lua) for design script
-- `text`, named `name` (default "test").
function Designs.request(text, facing, tileX, tileY, name, config)
	return { design = name or "test", blueprint = Designs.blueprint(text, config), facing = facing, tileX = tileX, tileY = tileY }
end

return Designs
