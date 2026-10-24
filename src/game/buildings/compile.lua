-- The compiler (docs/CONTEXT.md "Blueprint", ADR 0007): a design script's
-- resolved node tree turned into a blueprint (src/game/buildings/blueprint.lua),
-- the only thing the simulation reads. Pure; plain LuaJIT.
--
-- Geometry is clipped at the ground and footprinted from its bounds; the
-- blueprint's model space puts the footprint's north-west corner on (0, 0).
-- Roles come from the tree's role nodes (role prefabs place them).
local Resolve = require("src.game.script.resolve")
local Mesh = require("src.game.geometry.mesh")
local Footprint = require("src.game.geometry.footprint")
local Voxelise = require("src.game.geometry.voxelise")
local Blueprint = require("src.game.buildings.blueprint")
local WalkGrid = require("src.game.buildings.walk_grid")

local Compile = {}

-- Every role node under `node`, with where its origin lands once every
-- transform above it applies: { { role, x, y, z, name, brick }, ... }
-- appended to `out`. `brick` is the geometry of the node holding the role
-- (a role prefab's group: the function brick), as placed; `name` the id of
-- the nearest prefab instance holding it, else its own.
local function roles(node, out)
	local own = {}
	if node.kind == "role" then
		own[1] = { role = node.role, x = 0, y = 0, z = 0, name = node.id }
	end
	for _, child in ipairs(node.children or {}) do
		roles(child, own)
	end
	for _, r in ipairs(own) do
		r.x, r.y, r.z = Mesh.transformPoint(node.transform, r.x, r.y, r.z)
		if r.brick then
			r.brick = Mesh.transform(r.brick, node.transform)
		elseif node.kind ~= "role" then
			r.brick = Mesh.ofTree(node)
		end
		if node.kind == "prefab" and not r.inPrefab then
			r.name, r.inPrefab = node.id or r.name, true
		end
		out[#out + 1] = r
	end
	return out
end

-- The ground a function brick role `r` (Compile's roles) stands on, in
-- model space shifted by (ox, oy): its brick's bounds, or its own point
-- when the brick has no geometry.
local function brickArea(r, ox, oy)
	local b = r.brick and Mesh.bounds(r.brick)
	if not b then
		return { minX = r.x - ox, minY = r.y - oy, maxX = r.x - ox, maxY = r.y - oy }
	end
	return { minX = b.minX - ox, minY = b.minY - oy, maxX = b.maxX - ox, maxY = b.maxY - oy }
end

-- `triangles` moved by (dx, dy).
local function shifted(triangles, dx, dy)
	return Mesh.transform(triangles, { move = { dx, dy, 0 } })
end

local function clamp(v, lo, hi)
	return math.max(lo, math.min(hi, v))
end

-- Port position (x, y) in a w x d footprint snapped to the nearest edge,
-- at ground level (docs/CONTEXT.md "Role prefab"): on the middle of that
-- edge's row of tiles, and slid along it to stay on the footprint. A point
-- beyond an edge is nearest that edge. Returns edge, x, y.
local function snapPort(x, y, w, d)
	local edges = { { "N", y }, { "E", w - x }, { "S", d - y }, { "W", x } }
	local edge, nearest = nil, math.huge
	for _, e in ipairs(edges) do
		if e[2] < nearest then
			edge, nearest = e[1], e[2]
		end
	end
	x, y = clamp(x, 0.5, w - 0.5), clamp(y, 0.5, d - 0.5)
	if edge == "N" then
		y = 0.5
	elseif edge == "S" then
		y = d - 0.5
	elseif edge == "W" then
		x = 0.5
	else
		x = w - 0.5
	end
	return edge, x, y
end

local function add(cost, items, times)
	for item, n in pairs(items or {}) do
		cost[item] = (cost[item] or 0) + n * times
	end
end

-- `cost` with every count rounded up to whole items.
local function whole(cost)
	for item, n in pairs(cost) do
		cost[item] = math.ceil(n - 1e-9)
	end
	return cost
end

-- What `voxels` ({ [material] = count }) cost: per material, one of each
-- item per cfg.voxelsPerItem[material][item] voxels, rounded up.
local function voxelCost(voxels, cfg)
	local cost = {}
	for material, count in pairs(voxels) do
		for item, per in pairs(cfg.voxelsPerItem[material] or {}) do
			cost[item] = (cost[item] or 0) + math.ceil(count / per - 1e-9)
		end
	end
	return cost
end

-- What `found` roles cost (cfg.roleCosts), rounded up; or nil and a
-- message for an ability the game doesn't know.
local function roleCost(found, cfg)
	local costs, cost = cfg.roleCosts, {}
	for _, a in ipairs(found.abilities) do
		local items = costs.abilities[a.ability]
		if not items then
			return nil, "unknown ability \"" .. a.ability .. "\""
		end
		add(cost, items, 1)
	end
	for _, p in ipairs(found.ports) do
		add(cost, costs.ports[p.kind], 1)
	end
	add(cost, costs.storagePerItem, found.storage)
	return whole(cost)
end

local TRAITS = { "productivity", "capacity", "reach", "health" }
local AURAS = { "walkSpeed", "harvestRate" }

-- Totals of `names` over `voxels` ({ [material] = count }): each material's
-- `perMaterial[material]` once per cfg.traitVoxels of its voxels.
local function perVoxel(voxels, names, perMaterial, cfg)
	local totals = {}
	for _, name in ipairs(names) do
		totals[name] = 0
	end
	for material, count in pairs(voxels) do
		local values = perMaterial[material] or {}
		for _, name in ipairs(names) do
			totals[name] = totals[name] + (values[name] or 0) * count / cfg.traitVoxels
		end
	end
	return totals
end

-- The parts of `root` clipped at the ground, each with its material (the
-- default when its vertices have none): { { triangles, material }, ... }.
local function materialParts(root, cfg)
	local out = {}
	for i, triangles in ipairs(Mesh.parts(root)) do
		local first = triangles[1]
		out[i] = { triangles = Mesh.clip(triangles), material = first and first.material or cfg.defaultMaterial }
	end
	return out
end

-- The blueprint of the resolved tree under `root`, or nil and a message.
-- Its walk grid (src/game/buildings/walk_grid.lua) comes from its voxels;
-- a function brick or bed no doorway leads to fails as "<id> can't be
-- reached from outside" (docs/CONTEXT.md "Doorway"), <id> its prefab
-- instance's.
function Compile.blueprint(root, config)
	local cfg = config.blueprints
	local parts = materialParts(root, cfg)
	local triangles = {}
	for i, part in ipairs(parts) do
		triangles[i] = part.triangles
	end
	triangles = Mesh.merge(triangles)
	local footprint = Footprint.of(Mesh.bounds(triangles))
	if not footprint then
		return nil, "the design has no geometry above ground"
	end
	local ox, oy = footprint.x, footprint.y
	local found = { abilities = {}, ports = {}, storage = 0 }
	local bricks = {}
	for _, r in ipairs(roles(root, {})) do
		local x, y = r.x - ox, r.y - oy
		if r.role.ability then
			table.insert(found.abilities, { ability = r.role.ability, x = x, y = y })
			bricks[#bricks + 1] = { name = r.name or r.role.ability, area = brickArea(r, ox, oy) }
		elseif r.role.port then
			local edge, px, py = snapPort(x, y, footprint.width, footprint.depth)
			table.insert(found.ports, { kind = r.role.port, edge = edge, x = px, y = py })
		else
			found.storage = found.storage + r.role.storage
		end
	end
	local cost, message = roleCost(found, cfg)
	if not cost then
		return nil, message
	end
	local voxels, centres = Voxelise.of(parts, cfg.voxelsPerTile)
	add(cost, voxelCost(voxels, cfg), 1)
	for _, v in ipairs(centres) do
		v.x, v.y = v.x - ox, v.y - oy
	end
	local walk = WalkGrid.of(centres, footprint.width, footprint.depth, config.walk)
	for _, brick in ipairs(bricks) do
		if not WalkGrid.reaches(walk, brick.area, config.walk.cellsPerTile) then
			return nil, brick.name .. " can't be reached from outside"
		end
	end
	local blueprint = {
		width = footprint.width,
		depth = footprint.depth,
		walk = walk,
		mesh = shifted(triangles, -ox, -oy),
		roles = found,
		cost = cost,
		traits = perVoxel(voxels, TRAITS, config.traits, cfg),
		auras = perVoxel(voxels, AURAS, config.auras, cfg),
	}
	blueprint.hash = Blueprint.hash(blueprint)
	return blueprint
end

-- Why `blueprint` may not be placed as a building, as reasons in rule
-- order; empty when it may (docs/CONTEXT.md "Function brick"): "no
-- function role" (it has no ability), then "<ability> without input" for
-- each converting ability (config.production.recipes) when it has no
-- input port to take its input from.
function Compile.problems(blueprint, config)
	local roles, problems = blueprint.roles, {}
	if #roles.abilities == 0 then
		problems[#problems + 1] = "no function role"
	end
	local inputs = 0
	for _, p in ipairs(roles.ports) do
		if p.kind == "input" then
			inputs = inputs + 1
		end
	end
	local seen = {}
	for _, a in ipairs(roles.abilities) do
		if config.production.recipes[a.ability] and inputs == 0 and not seen[a.ability] then
			seen[a.ability] = true
			problems[#problems + 1] = a.ability .. " without input"
		end
	end
	return problems
end

-- The blueprint of design script `text` (named `name` in messages), its
-- prefabs resolved from `library` (src/game/script/resolve.lua), or nil
-- and a message.
function Compile.design(text, name, library, config)
	local result, message = Resolve.design(text, name, library)
	if not result then
		return nil, message
	end
	return Compile.blueprint(result.root, config)
end

return Compile
