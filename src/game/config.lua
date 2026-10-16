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

	-- The world the app opens with, in tiles.
	world = { width = 128, height = 128 },

	-- Seeded world generation (src/game/world_gen.lua). Distances in tiles;
	-- {min, max} pairs are random ranges. spawnClearRadius keeps the world's
	-- centre free grass: the starting storage facility (3x2 tiles and its
	-- port tiles), the player beside it, and room for the villagers.
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
		tree = { amount = 10, item = "log", stageAt = { 0.6, 0.3 }, growTime = 120 },
		rock = { amount = 8, item = "stone", stageAt = { 0.6, 0.3 } },
	},

	-- Hand harvesting: seconds per cycle (each yields 1 item) and how near
	-- the character may stand, in px from its centre to the node's tile.
	harvest = { handCycle = 0.5, reach = 12 },

	-- The stockpile: the planks and stone a new game's starting storage
	-- facility (src/game/designs/starter.lua) holds. The player's inventory
	-- starts empty.
	stockpile = { plank = 50, stone = 50 },

	-- What placing a building costs (src/game/builder/cost.lua): items per
	-- baseplate tile, and items per stud of each brick's footprint by its
	-- material. Function, port and storage bricks add their own `cost`
	-- (builder.bricks) on top.
	costs = {
		baseplatePerTile = { plank = 2 },
		perStud = { plank = { plank = 1 }, stone = { stone = 1 } },
	},

	-- What each brick adds to its design's traits (src/game/builder/traits.lua)
	-- by its material. Productivity shortens cycles, capacity grows buffers
	-- and storage, reach sets harvest and aura radius, health does nothing yet.
	traits = {
		plank = { productivity = 1, capacity = 1, reach = 1, health = 1 },
		stone = { productivity = -1, capacity = 1, reach = 0, health = 3 },
	},

	-- Auras (docs/CONTEXT.md "Aura"): what each brick of a material adds to
	-- its building's aura. Fractions: 0.1 is +10%. walkSpeed scales the
	-- character's walk speed, harvestRate its hand-harvest speed, while it
	-- is within the building's reach. Auras of several buildings add up.
	auras = {
		plank = { walkSpeed = 0.05, harvestRate = 0 },
		stone = { walkSpeed = 0, harvestRate = 0.1 },
	},

	-- Building production (src/game/components/{function_brick,ports,storage}.lua).
	--   abilities: the node kind each harvesting function brick works.
	--   harvestCycle: seconds per item for one function brick at
	--     productivity 0. Each productivity point adds productivityStep to
	--     its speed (cycle = harvestCycle / speed), never below minSpeed.
	--   reachBase, reachPerPoint: a building harvests nodes within
	--     reachBase + floor(reach * reachPerPoint) tiles of its footprint,
	--     counted in whole tiles in any direction (diagonals count as one),
	--     so 1 means the ring of tiles touching the footprint.
	--   bufferSize: items one port buffer holds at capacity 0.
	--   capacityStep: each capacity point grows buffers and storage by this
	--     fraction of their base size (rounded down).
	production = {
		abilities = { saw = "tree", pickaxe = "rock" },
		-- planters: the node kind each planter ability plants, one sapling
		-- per plantCycle seconds (scaled like harvestCycle). A sapling takes
		-- nodes.<kind>.growTime seconds to grow (first half sapling, then young).
		planters = { planter = "tree" },
		plantCycle = 6,
		harvestCycle = 3,
		-- recipes: converting function bricks by ability; each cycle (seconds
		-- at productivity 0, scaled like harvestCycle) takes `input` items
		-- from input buffers or storage and yields one `output` item.
		recipes = { sawbench = { input = { log = 2 }, output = "plank", cycle = 4 } },
		productivityStep = 0.02,
		minSpeed = 0.25,
		reachBase = 2,
		reachPerPoint = 0.25,
		bufferSize = 4,
		capacityStep = 0.05,
	},

	-- Props (src/game/props/): seeded variants per kind, baked once into a
	-- cache under the save directory (src/app/bake/prop_cache.lua). seed is
	-- the base every (kind, variant) seed derives from; changing it, or
	-- variants, rebakes every kind.
	props = { variants = 8, seed = 1, cacheDir = "props" },

	-- The design library (src/game/designs/, src/app/design_store.lua): one
	-- file per design under `dir` in the save directory, shared by every
	-- world. Names are labels of at most maxNameLength characters.
	designs = { dir = "designs", maxNameLength = 24 },

	-- The one world save slot (src/game/save/codec.lua,
	-- src/app/save_store.lua): a file in the save directory. seed is the
	-- world seed a new game starts from.
	save = { file = "world.save", seed = 1 },

	character = {
		size = 16, -- placeholder square side, px
		speed = 160, -- walk speed, px/s
		-- px walked per walk-cycle frame (src/game/components/animator.lua);
		-- the 4-frame cycle repeats every 4 * walkFrameDistance px.
		walkFrameDistance = 10,
	},

	-- Villagers (docs/CONTEXT.md "Villager"): a new game spawns `count` on
	-- free tiles within spawnRadius tiles of the starting storage facility's
	-- footprint. size and speed as for the character. shirt is their shirt
	-- colour, apart from the player's. A path search (src/game/pathfind.lua)
	-- gives up after pathMaxExpansions tiles, so a target walled off by water
	-- never scans the whole world. carryLimit is the most items one load
	-- (src/game/components/load.lua) holds, so one haul trip moves.
	-- buildTime is the seconds a build job (src/game/jobs/build.lua) takes
	-- per footprint tile of the construction site.
	villagers = {
		carryLimit = 4,
		buildTime = 1,
		count = 20,
		spawnRadius = 6,
		size = 16,
		speed = 120,
		shirt = { 0.72, 0.36, 0.2 },
		pathMaxExpansions = 4000,
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
		--
		-- Function, port and storage bricks (docs/CONTEXT.md) carry their
		-- role, copied onto every brick placed: `ability` (what the building
		-- can do), `port` ("input" | "output") or `storage` (items it
		-- holds). Each adds its own `cost` (src/game/builder/cost.lua) and
		-- draws its own model from `layers`: bottom layer first, each a list
		-- of stud rows north to south, one character per stud west to east:
		--   "." empty, "#" box in paint and material, "o" box in `accent`,
		--   "N" "E" "S" "W" a slope in paint looking that way, "n" "e" "s"
		--   "w" the same in accent. Accent studs have no material.
		-- A shape without `layers` is one layer of boxes (and its `slope`).
		-- `label` names the sidebar button (the name when absent).
		bricks = {
			{ name = "1x1", width = 1, depth = 1 },
			{ name = "1x2", width = 2, depth = 1 },
			{ name = "1x4", width = 4, depth = 1 },
			{ name = "2x2", width = 2, depth = 2 },
			{ name = "2x4", width = 4, depth = 2 },
			{ name = "slope", width = 2, depth = 2, slope = "S" },
			{
				name = "saw",
				label = "Saw",
				ability = "saw",
				width = 3,
				depth = 1,
				cost = { stone = 4 },
				accent = { 0.78, 0.8, 0.82 },
				layers = { { "###" }, { "ooo" }, { "woe" } },
			},
			{
				name = "pickaxe",
				label = "Pickaxe",
				ability = "pickaxe",
				width = 3,
				depth = 1,
				cost = { stone = 4 },
				accent = { 0.45, 0.47, 0.5 },
				layers = { { ".#." }, { ".#." }, { "woe" } },
			},
			{
				name = "planter",
				label = "Planter",
				ability = "planter",
				width = 2,
				depth = 2,
				cost = { plank = 4 },
				accent = { 0.3, 0.7, 0.25 },
				layers = { { "##", "##" }, { "o.", ".o" } },
			},
			{
				name = "sawbench",
				label = "Saw bench",
				ability = "sawbench",
				width = 4,
				depth = 2,
				cost = { plank = 4, stone = 2 },
				accent = { 0.78, 0.8, 0.82 },
				layers = { { "#..#", "#..#" }, { "####", "####" }, { ".we.", "...." } },
			},
			-- The depot (docs/CONTEXT.md "Depot") makes its building a
			-- storage facility: it needs no operator and its input port
			-- accepts every item.
			{
				name = "depot",
				label = "Depot",
				ability = "depot",
				width = 2,
				depth = 2,
				cost = { plank = 4 },
				accent = { 0.55, 0.36, 0.18 },
				layers = { { "##", "##" }, { "oo", "oo" }, { "#.", ".#" } },
			},
			{
				name = "input",
				label = "Input port",
				port = "input",
				width = 2,
				depth = 1,
				cost = { plank = 1 },
				accent = { 0.25, 0.5, 0.95 },
				layers = { { "oo" } },
			},
			{
				name = "output",
				label = "Output port",
				port = "output",
				width = 2,
				depth = 1,
				cost = { plank = 1 },
				accent = { 0.95, 0.55, 0.15 },
				layers = { { "oo" } },
			},
			{
				name = "storage",
				label = "Storage",
				storage = 8,
				width = 2,
				depth = 2,
				cost = { plank = 4 },
				accent = { 0.3, 0.2, 0.12 },
				layers = { { "##", "##" }, { "oo", "oo" } },
			},
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
		-- The info panel right of the view: traits, cost, design problems.
		infoWidth = 200,
		colors = {
			baseplate = { 0.3, 0.55, 0.3 },
			baseplateStud = { 0.34, 0.6, 0.34 },
		},
	},
}
