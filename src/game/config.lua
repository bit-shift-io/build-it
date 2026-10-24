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

	-- Views: plain data Projection.new turns into world<->screen math. A view
	-- is { ground = { a, b, c, d }, lift, depth = { x, y } }, in tiles:
	--   screen x = a*x + b*y            (times pixels per tile)
	--   screen y = c*x + d*y - lift*z
	--   depth    = depth.x*x + depth.y*y + z   (larger is nearer the viewer)
	-- The depth coefficients are the view ray (dx, dy, 1): points a ray apart
	-- share a pixel. Solving ground * (dx, dy) = (0, lift) gives them.
	-- Keep lift * tileSize / 16 whole in every view so voxel heights stay on
	-- whole pixels.
	--
	-- Isometric views turn the ground 45 degrees (x east runs down-right, y
	-- south down-left; the viewer is at the south-east corner). With pitch p
	-- above the horizon a ground unit of length s draws cos45*s wide and
	-- cos45*sin(p)*s tall, and a unit of height draws cos(p)*s tall. Taking
	-- the tile edge to draw one tile wide fixes s = sqrt(2), so
	--   ground y per tile = sin(p),  lift = sqrt(2) * cos(p).
	-- Lift is then rounded to the nearest 0.5 to keep tileSize / 16 whole.
	views = {
		-- Identical to the original 3/4 top-down projection.
		topdown = {
			ground = { 1, 0, 0, 1 },
			lift = 1,
			depth = { 0, 1 },
		},
		-- 2:1 dimetric: ground diamond half-width tileSize, half-height
		-- tileSize / 2. Pitch atan(1/2) = 26.57 degrees, the pixel-art
		-- pitch; ground y per tile 1/2. Exact lift sqrt(2)*cos(26.57) = 1.265,
		-- rounded to 1.5. Depth: dx = dy = lift / (c + d) = 1.5.
		iso2to1 = {
			ground = { 1, -1, 0.5, 0.5 },
			lift = 1.5,
			depth = { 1.5, 1.5 },
		},
		-- True isometric: pitch atan(1/sqrt(2)) = 35.26 degrees; ground y
		-- per tile sin(p) = 1/sqrt(3) = 0.5774. Exact lift sqrt(2)*cos(35.26)
		-- = 1.155, rounded to 1.0. Depth: dx = dy = 1 / (2/sqrt(3)) = 0.866.
		iso = {
			ground = { 1, -1, 0.5773502691896258, 0.5773502691896258 },
			lift = 1,
			depth = { 0.8660254037844386, 0.8660254037844386 },
		},
		-- 3/4 top-down sheared so the viewer stands to the south-west: moving
		-- south also moves right on screen (screen x = x + 0.1*y), tile edges
		-- along x stay level, and the west faces of buildings show beside the
		-- south faces. Lift stays 1 and straight up. Depth: ground * (dx, dy)
		-- = (0, lift) gives dy = 1, dx = -0.1.
		skew = {
			ground = { 1, 0.1, 0, 1 },
			lift = 1,
			depth = { -0.1, 1 },
		},
	},

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
		bushPatches = { count = 14, radius = { 2, 4 }, density = 0.5, falloff = 0.5 },
		-- Deer herds (docs/CONTEXT.md "Herd"): each gets a home tile on
		-- free grass outside the spawn clearing and a cap drawn from `cap`,
		-- and starts at that cap, its deer within `spread` tiles of home.
		herds = { count = 10, cap = { 3, 6 }, spread = 2 },
	},

	-- Animals (src/game/systems/animal_system.lua). A deer wanders to a
	-- random standable tile within wanderRadius tiles of its herd's home
	-- every wanderEvery seconds (a range). A herd under its cap adds a deer
	-- every breedEvery seconds. size and speed are in px and px/s.
	animals = {
		deer = { size = 7, speed = 45, wanderRadius = 4, wanderEvery = { 3, 8 }, breedEvery = 60 },
	},

	-- Resource nodes: what a fresh node of each kind holds, the item one
	-- harvest cycle takes from it, and stageAt: the remaining fractions at or
	-- below which it steps to stage 2, 3, ... A node at 0 is depleted and
	-- vanishes, freeing its tile. A bush is the exception: picked clean (its
	-- last stage) it refills after refillTime seconds and never vanishes.
	nodes = {
		tree = { amount = 10, item = "log", stageAt = { 0.6, 0.3 }, growTime = 120 },
		rock = { amount = 8, item = "stone", stageAt = { 0.6, 0.3 } },
		bush = { amount = 6, item = "berry", stageAt = { 0.5, 0.01 }, refillTime = 90 },
	},

	-- Hand harvesting: seconds per cycle (each yields 1 item) and how near
	-- the character may stand, in px from its centre to the node's tile.
	harvest = { handCycle = 0.5, reach = 12 },

	-- Names (docs/CONTEXT.md "Name"): the fixed list the player and each
	-- villager draw from with ctx.rng at spawn.
	names = {
		"Ada", "Bram", "Cleo", "Dov", "Edda", "Finn", "Gwen", "Hugo", "Iris", "Jory",
		"Kit", "Lena", "Milo", "Nora", "Otto", "Pia", "Quin", "Rhea", "Seth", "Tess",
		"Uma", "Vic", "Wren", "Xavi", "Yara", "Zed",
	},

	-- Needs (src/game/components/needs.lua): every meter is a fraction 0..1,
	-- rates in fractions per second. A meal falls due (hunger reaches
	-- hungryAt) about every 3 min, sleep (tiredness reaches tiredAt) about
	-- every 8 min. At full hunger health drains from full to collapse in
	-- about 2 min; below starvingAt it regenerates.
	needs = {
		hungerRate = 0.6 / 180,
		hungryAt = 0.6,
		tirednessRate = 0.7 / 480,
		tiredAt = 0.7,
		starvingAt = 0.9,
		drainRate = 1 / 120,
		regenRate = 1 / 60,
		-- Tiredness a sleeper loses per second (it stops rising while
		-- asleep): in a bed about a minute from the tired threshold, on
		-- the ground three times slower (docs/CONTEXT.md "Bed").
		bedRestRate = 0.7 / 60,
		groundRestRate = 0.7 / 180,
	},

	-- Food (docs/CONTEXT.md "Food", "Meal"): the hunger each item takes away
	-- (a fraction of the 0..1 meter). eatTime: seconds a villager takes to
	-- eat one item. facilityReach: whole tiles from a storage facility's
	-- footprint within which the player may eat from its storage (F).
	food = {
		berry = { fill = 0.2 },
		meat = { fill = 0.5 },
		fish = { fill = 0.4 },
	},
	eatTime = 0.5,
	facilityReach = 3,

	-- The stockpile: the items a new game's starting storage facility
	-- (src/game/designs/starter.lua) holds. The player's inventory starts
	-- empty.
	-- Sized so it pays for the first chain together (woodcutter, sawmill,
	-- forester, fishing hut, quarry: about 74 plank and 78 stone); a test
	-- (tests/unit/starter_content_test.lua) keeps that true.
	stockpile = { plank = 100, stone = 100, berry = 20 },

	-- Materials (docs/CONTEXT.md "Material", "Texture variant"): what a
	-- design's nodes may be made of, each with its texture variants in menu
	-- order, the first the default. The material sets cost and traits; the
	-- variant only how the shader (src/app/bake/block_shader.glsl) draws it.
	materials = {
		plank = { variants = { "polished", "bark", "shingles", "logs" } },
		stone = { variants = { "polished", "rough", "jagged", "brick" } },
	},

	-- What each blueprints.traitVoxels voxels of a material add to a
	-- design's traits (src/game/buildings/compile.lua). Productivity
	-- shortens cycles, capacity grows buffers and storage, reach sets
	-- harvest and aura radius, health does nothing yet.
	traits = {
		plank = { productivity = 1, capacity = 1, reach = 1, health = 1 },
		stone = { productivity = -1, capacity = 1, reach = 0, health = 3 },
	},

	-- Auras (docs/CONTEXT.md "Aura"): what each blueprints.traitVoxels
	-- voxels of a material add to its building's aura. Fractions: 0.001 is +0.1%. walkSpeed scales the
	-- character's walk speed, harvestRate its hand-harvest speed, while it
	-- is within the building's reach. Auras of several buildings add up.
	auras = {
		plank = { walkSpeed = 0.0005, harvestRate = 0 },
		stone = { walkSpeed = 0, harvestRate = 0.001 },
	},

	-- Compiled designs (src/game/buildings/compile.lua; ADR 0006): cost
	-- and traits come from the model's voxels, voxelsPerTile to a tile
	-- side, counted by material. Geometry with no material is
	-- defaultMaterial.
	--   voxelsPerItem[material][item]: voxels per item they cost, rounded
	--     up per material. 256 is about one brick.
	--   traitVoxels: voxels of a material per point of its traits
	--     (config.traits) and auras (config.auras); 256 is about one brick.
	--   roleCosts: what each role adds on top (docs/CONTEXT.md "Role
	--     prefab"): per ability, per port kind, and per storage item.
	blueprints = {
		voxelsPerTile = 16,
		defaultMaterial = "plank",
		voxelsPerItem = { plank = { plank = 256 }, stone = { stone = 256 } },
		traitVoxels = 256,
		roleCosts = {
			abilities = {
				saw = { stone = 4 },
				pickaxe = { stone = 4 },
				forager = { plank = 4 },
				fishing = { plank = 4 },
				hunter = { plank = 4 },
				planter = { plank = 4 },
				sawbench = { plank = 4, stone = 2 },
				depot = { plank = 4 },
				bed = { plank = 3 },
				canteen = { plank = 4 },
			},
			ports = { input = { plank = 1 }, output = { plank = 1 } },
			storagePerItem = { plank = 0.5 },
		},
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
	--   abilityReach: reachBase for a harvesting ability, where it differs.
	--   bufferSize: items one port buffer holds at capacity 0.
	--   capacityStep: each capacity point grows buffers and storage by this
	--     fraction of their base size (rounded down).
	production = {
		abilities = { saw = "tree", pickaxe = "rock", forager = "bush" },
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
		reachBase = 10,
		abilityReach = { saw = 10, fishing = 10, hunter = 10 },
		-- fishers: the item each fishing ability catches, one per fishCycle
		-- seconds (scaled like harvestCycle) from any water tile in reach,
		-- without limit.
		fishers = { fishing = "fish" },
		fishCycle = 8,
		-- hunters: the item each hunter ability yields per deer killed
		-- (meatPerDeer of it, at most villagers.carryLimit); a kill takes
		-- huntCycle seconds (scaled like harvestCycle) once the operator
		-- stands at the deer.
		hunters = { hunter = "meat" },
		huntCycle = 4,
		meatPerDeer = 3,
		reachPerPoint = 0.25,
		bufferSize = 4,
		capacityStep = 0.05,
	},

	-- Props (src/game/props/): seeded variants per kind, baked once into a
	-- cache under the save directory (src/app/bake/prop_cache.lua). seed is
	-- the base every (kind, variant) seed derives from; changing it, or
	-- variants, rebakes every kind.
	props = { variants = 8, seed = 1, cacheDir = "props" },

	-- The design library (src/game/designs/library.lua,
	-- src/app/design_store.lua): one Lua file per design under `dir` and per
	-- prefab under `prefabDir` in the save directory, shared by every world
	-- and named by file name. They shadow the built-ins of the same name
	-- (src/game/designs/builtins.lua).
	designs = { dir = "designs", prefabDir = "prefabs" },

	-- The one world save slot (src/game/save/codec.lua,
	-- src/app/save_store.lua): a file in the save directory. seed is the
	-- world seed a new game starts from.
	save = { file = "world.save", seed = 1 },

	-- Player settings (src/game/settings.lua, src/app/settings_store.lua): a
	-- file in the save directory, shared by every world.
	settings = { file = "settings.cfg" },

	-- Walk grid (docs/adr/0008, src/game/buildings/walk_grid.lua): a
	-- blueprint's footprint split into cellsPerTile stud cells a tile side.
	-- A cell blocks when a voxel's centre lies in the body-height band, from
	-- floorClearance up to bodyHeight (tiles): lower geometry (floors, short
	-- fences) is stepped over, higher (roofs, lintels) walked under.
	-- bodyHeight is a figure's height, 15 voxels on the 32-per-tile figure
	-- grid.
	walk = { cellsPerTile = 4, floorClearance = 0.25, bodyHeight = 15 / 32 },

	character = {
		size = 8, -- placeholder square side, px
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
		size = 8,
		speed = 120,
		shirt = { 0.72, 0.36, 0.2 },
		pathMaxExpansions = 4000,
		-- Experience (v.xp, one count per role: haul, build, each brick
		-- ability): +1 per finished haul trip, operator cycle and build.
		-- In a job pick, a villager counts as bonusTiles nearer at `cap`
		-- experience in the role, scaling up from none; counts past cap
		-- keep growing but earn nothing more.
		experience = { cap = 20, bonusTiles = 4 },
		-- Free villagers idle in the gather area (docs/CONTEXT.md): tiles
		-- gatherMin..gatherRadius from a storage facility's footprint.
		-- personalSpace (tiles): settled villagers keep this far from others.
		-- driftSpeed: fraction of walk speed at full push. deadZone: pushes
		-- weaker than this (0..1) are ignored, so the crowd rests.
		-- pullBack: strength (0..1) of the pull toward the facility once
		-- outside the gather radius.
		idle = {
			gatherMin = 1,
			gatherRadius = 5,
			portReach = 2, -- tiles: a hauler waits this near its source port tile
			personalSpace = 0.8,
			driftSpeed = 0.4,
			deadZone = 0.08,
			wakeFactor = 2, -- a resting villager needs deadZone * wakeFactor to move
			pullBack = 0.5,
			-- Idle life: seconds between turns on the spot and between short
			-- wanders; wanderDistance (tiles) is how far a wander may reach.
			turnEvery = { 2, 5 },
			wanderEvery = { 5, 10 },
			wanderDistance = 1.5,
		},
	},

	camera = {
		minZoom = 0.25,
		maxZoom = 4,
		zoomStep = 1.1, -- zoom factor per wheel notch
	},

	-- The script builder (src/app/screens/script_builder.lua). testDesign is
	-- the design script it opens, read from the game's files. The top bar
	-- holds topBarSlots numbered tool slots, topBarHeight pixels tall. It
	-- shares builder.camera's orbit and draws in builder studs (studsPerTile
	-- per tile).
	scriptBuilder = {
		testDesign = "content/designs/test.lua",
		topBarSlots = 9,
		topBarHeight = 40,
	},

	-- The builder's orbit camera (src/app/builder_camera.lua), which draws
	-- in studs, studsPerTile to a tile side.
	builder = {
		studsPerTile = 4,
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
	},
}
