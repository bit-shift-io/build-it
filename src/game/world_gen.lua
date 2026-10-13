-- Seeded world generation: grass, water blobs, then clusters of tree and
-- rock resource nodes on the grass. The same seed always gives the same
-- world (docs/ARCHITECTURE.md "Rules"). Pure -- no `love.*`.
--
-- Tuning: config.world (size), config.worldGen (blobs and clusters),
-- config.nodes (per-kind amounts), config.props.variants.
local Rng = require("src.core.rng")
local World = require("src.game.world")

local WorldGen = {}

local function clearOfSpawn(world, cfg, x, y)
	local dx, dy = x + 0.5 - world.width / 2, y + 0.5 - world.height / 2
	return dx * dx + dy * dy > cfg.spawnClearRadius * cfg.spawnClearRadius
end

-- Calls fn(x, y, d) for every in-world tile whose centre lies within r of
-- (cx, cy), d being that distance. Row-major, so the order is fixed.
local function eachTileWithin(world, cx, cy, r, fn)
	for y = math.max(0, math.floor(cy - r)), math.min(world.height - 1, math.ceil(cy + r)) do
		for x = math.max(0, math.floor(cx - r)), math.min(world.width - 1, math.ceil(cx + r)) do
			local dx, dy = x + 0.5 - cx, y + 0.5 - cy
			local d = math.sqrt(dx * dx + dy * dy)
			if d <= r then
				fn(x, y, d)
			end
		end
	end
end

-- A water blob: a few overlapping round lobes around one centre.
local function addWater(world, rng, cfg)
	local w = cfg.water
	for _ = 1, w.blobs do
		local cx, cy = rng:range(0, world.width), rng:range(0, world.height)
		for _ = 1, rng:int(w.lobes[1], w.lobes[2]) do
			local lx, ly = cx + rng:range(-w.lobeSpread, w.lobeSpread), cy + rng:range(-w.lobeSpread, w.lobeSpread)
			eachTileWithin(world, lx, ly, rng:range(w.lobeRadius[1], w.lobeRadius[2]), function(x, y)
				if clearOfSpawn(world, cfg, x, y) then
					World.setTerrain(world, x, y, "water")
				end
			end)
		end
	end
end

-- Clusters of one node kind: denser toward each cluster's centre, only on
-- free grass outside the spawn clearing.
local function addClusters(world, rng, config, kind, cluster)
	local cfg = config.worldGen
	for _ = 1, cluster.count do
		local cx, cy = rng:range(0, world.width), rng:range(0, world.height)
		local r = rng:range(cluster.radius[1], cluster.radius[2])
		eachTileWithin(world, cx, cy, r, function(x, y, d)
			local chance = cluster.density * (1 - cluster.falloff * d / r)
			if rng:next() < chance
				and World.terrainAt(world, x, y) == "grass"
				and not World.nodeAt(world, x, y)
				and clearOfSpawn(world, cfg, x, y)
			then
				World.addNode(world, {
					id = #world.nodes + 1,
					kind = kind,
					tileX = x,
					tileY = y,
					variant = rng:int(1, config.props.variants),
					stage = 1,
					amount = config.nodes[kind].amount,
				})
			end
		end)
	end
end

-- A new world from config and seed: { width, height, terrain, nodes, nodeAt }
-- (src/game/world.lua).
function WorldGen.generate(config, seed)
	local world = World.new(config.world.width, config.world.height)
	local rng = Rng.new(Rng.hash("world", seed))
	addWater(world, rng, config.worldGen)
	addClusters(world, rng, config, "tree", config.worldGen.forests)
	addClusters(world, rng, config, "rock", config.worldGen.rockFields)
	return world
end

return WorldGen
