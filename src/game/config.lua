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

	-- Resource nodes: what a fresh node of each kind holds.
	nodes = {
		tree = { amount = 10 },
		rock = { amount = 8 },
	},

	-- Props (src/game/props/): seeded variants per kind, baked once into a
	-- cache under the save directory (src/app/bake/prop_cache.lua). seed is
	-- the base every (kind, variant) seed derives from; changing it, or
	-- variants, rebakes every kind.
	props = { variants = 8, seed = 1, cacheDir = "props" },

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
		brick = { width = 2, depth = 2 }, -- studs
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
			brick = { 0.8, 0.25, 0.2 },
			brickAlt = { 0.72, 0.22, 0.18 },
		},
	},
}
