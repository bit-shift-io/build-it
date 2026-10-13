-- Every tuning number in the game lives here (docs/ARCHITECTURE.md "Rules").
-- Systems and components read it through ctx.config, so a test can pass an
-- override table instead.
return {
	-- Base pixels per tile side: the world at zoom 1, and baked sprites at
	-- bake scale 1. Sprites bake at whole multiples of it (Projection.bakeScale),
	-- so a stud is 8 px and a voxel 2 px at every bake scale. One tile is 4x4
	-- studs, 16x16 voxels.
	tileSize = 32,

	-- The one 3/4 top-down projection (src/game/projection.lua). Ground tiles
	-- stay square; one tile of height lifts a point heightScale tiles up the
	-- screen. Keep heightScale * tileSize / 16 whole so voxel heights stay
	-- on whole pixels.
	projection = { heightScale = 1 },

	-- Baked sprite lighting (src/app/bake/block_shader.glsl). lightDirection
	-- points from a surface toward the light, in model space (x east, y south,
	-- z up); it need not be unit length. ambient is the light on faces the
	-- light misses.
	bake = {
		lightDirection = { -0.4, 0.5, 1 },
		ambient = 0.45,
	},

	-- The hard-coded test house row (src/game/blocks/test_house.lua), in
	-- tiles from the world's centre tile, one house per facing.
	testHouses = { offsetX = -7, offsetY = -6, spacing = 4 },

	-- The world the app opens with, in tiles.
	world = { width = 128, height = 128 },

	-- Seeded world generation (src/game/world_gen.lua). Distances in tiles;
	-- {min, max} pairs are random ranges. spawnClearRadius keeps the world's
	-- centre (the character spawn and the test house row) free grass.
	-- Cluster density is the chance a tile at the centre gets a node; it
	-- falls by `falloff` of itself toward the cluster's edge.
	worldGen = {
		spawnClearRadius = 12,
		water = { blobs = 14, lobes = { 2, 4 }, lobeRadius = { 2, 6 }, lobeSpread = 4 },
		forests = { count = 24, radius = { 3, 8 }, density = 0.6, falloff = 0.6 },
		rockFields = { count = 18, radius = { 2, 4 }, density = 0.6, falloff = 0.5 },
	},

	-- Resource nodes: what a fresh node of each kind holds, the item one
	-- harvest cycle takes from it, and stageAt: the remaining fractions at or
	-- below which it steps to stage 2, 3, ... A node at 0 is depleted and
	-- vanishes, freeing its tile.
	nodes = {
		tree = { amount = 10, item = "log", stageAt = { 0.6, 0.3 } },
		rock = { amount = 8, item = "stone", stageAt = { 0.6, 0.3 } },
	},

	-- Hand harvesting: seconds per cycle (each yields 1 item) and how near
	-- the character may stand, in px from its centre to the node's tile.
	harvest = { handCycle = 0.5, reach = 12 },

	-- The planks and stone a new game's inventory starts with.
	stockpile = { plank = 50, stone = 50 },

	-- What placing a building costs (src/game/builder/cost.lua): items per
	-- baseplate tile. Placeholder until bricks carry their own costs.
	costs = { baseplatePerTile = { plank = 2 } },

	-- Props (src/game/props/): seeded variants per kind, baked once into a
	-- cache under the save directory (src/app/bake/prop_cache.lua). seed is
	-- the base every (kind, variant) seed derives from; changing it, or
	-- variants, rebakes every kind.
	props = { variants = 8, seed = 1, cacheDir = "props" },

	-- The design library (src/game/designs/, src/app/design_store.lua): one
	-- file per design under `dir` in the save directory, shared by every
	-- world. Names are labels of at most maxNameLength characters.
	designs = { dir = "designs", maxNameLength = 24 },

	character = {
		size = 16, -- placeholder square side, px
		speed = 160, -- walk speed, px/s
	},

	camera = {
		minZoom = 0.25,
		maxZoom = 4,
		zoomStep = 1.1, -- zoom factor per wheel notch
	},

	-- The builder screen (src/game/builder/, src/app/screens/builder.lua).
	-- Bricks sit on the stud grid (studsPerTile per tile side) and stack in
	-- layers one stud tall. The baseplate is minBaseplate..maxBaseplate tiles
	-- per side; no brick may reach above maxLayers.
	builder = {
		studsPerTile = 4,
		minBaseplate = 1,
		maxBaseplate = 4,
		maxLayers = 12,
		-- The brick palette (src/game/builder/bricks.lua), unturned
		-- footprints in studs. A slope's `slope` row is the edge it falls
		-- toward: one stud row of 45-degree slope, the rest full height.
		bricks = {
			{ name = "1x1", width = 1, depth = 1 },
			{ name = "1x2", width = 2, depth = 1 },
			{ name = "1x4", width = 4, depth = 1 },
			{ name = "2x2", width = 2, depth = 2 },
			{ name = "2x4", width = 4, depth = 2 },
			{ name = "slope", width = 2, depth = 2, slope = "S" },
		},
		materials = { "plank", "stone" },
		-- Paint colours, free and cosmetic; bricks store an index into it.
		palette = {
			{ 0.79, 0.1, 0.09 }, -- red
			{ 0.95, 0.47, 0.12 }, -- orange
			{ 0.98, 0.79, 0.05 }, -- yellow
			{ 0.95, 0.89, 0.71 }, -- tan
			{ 0.35, 0.67, 0.25 }, -- lime green
			{ 0.13, 0.45, 0.2 }, -- dark green
			{ 0.36, 0.69, 0.86 }, -- light blue
			{ 0.05, 0.3, 0.62 }, -- blue
			{ 0.54, 0.27, 0.62 }, -- purple
			{ 0.35, 0.2, 0.12 }, -- brown
			{ 0.95, 0.95, 0.95 }, -- white
			{ 0.1, 0.1, 0.1 }, -- black
		},
		-- The brick in hand when the builder opens.
		held = { shape = "2x2", rotation = 0, material = "plank", paint = 1 },
		-- Orbit camera, in studs and radians. distance is from the target;
		-- the camera never comes nearer than the model's bounding radius plus
		-- nearMargin, so orbiting and zooming never clip the model.
		camera = {
			fov = math.rad(45),
			yaw = math.rad(30),
			pitch = math.rad(40),
			minPitch = math.rad(8),
			maxPitch = math.rad(85),
			distance = 16,
			maxDistance = 80,
			nearMargin = 2,
			orbitSpeed = 0.01, -- radians per pixel dragged
			zoomStep = 1.1, -- distance factor per wheel notch
		},
		-- A right-button press that moves less than this many pixels before
		-- release is a click (remove a brick), not an orbit drag.
		clickSlop = 4,
		sidebarWidth = 200,
		colors = {
			baseplate = { 0.3, 0.55, 0.3 },
			baseplateStud = { 0.34, 0.6, 0.34 },
		},
	},
}
