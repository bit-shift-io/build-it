-- The shipped starter buildings under real LÖVE 12 (content/designs): each
-- drawn whole from outside, then cut away (docs/CONTEXT.md "Cutaway") with
-- the player and a villager standing inside its doorway. Checked by eye:
-- walls, roof, windows and a door outside; the bricks and figures inside.
-- Captures land in tests/screenshots/starters_render_test/.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local Inventory = require("src.game.components.inventory")
local Placement = require("src.game.buildings.placement")
local Projection = require("src.game.projection")
local Session = require("src.game.session")
local BuildingsRender = require("src.app.render.buildings")
local Designs = require("tests.support.designs")

local TILE = Config.tileSize

-- Its own prop cache folder, so the test never reads or writes the
-- player's (docs/memory/e2e-isolate-save-dir.md).
local function testConfig()
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.props = { variants = Config.props.variants, seed = Config.props.seed, cacheDir = "e2e_starters_props" }
	return config
end

-- Each starter, where it stands (facing north) and the middle of its
-- doorway in model tiles.
local STARTERS = {
	{ name = "storage_facility", x = 2, y = 9, door = 0.75 },
	{ name = "woodcutter", x = 7, y = 9, door = 1 },
	{ name = "quarry", x = 11, y = 9, door = 1 },
	{ name = "sawmill", x = 15, y = 9, door = 1.5 },
	{ name = "forager_hut", x = 20, y = 9, door = 1 },
	{ name = "fishing_hut", x = 2, y = 20, door = 1 },
	{ name = "hunter_lodge", x = 6, y = 20, door = 1 },
	{ name = "bedhouse", x = 10, y = 20, door = 1 },
	{ name = "canteen", x = 14, y = 20, door = 1 },
	{ name = "forester", x = 18, y = 20, door = 1 },
}

test("every starter draws as a walled, roofed building with a door, and cut away from inside", function()
	local config = testConfig()
	for _, name in ipairs(love.filesystem.getDirectoryItems(config.props.cacheDir)) do
		love.filesystem.remove(config.props.cacheDir .. "/" .. name)
	end
	local world = World.new(30, 30)
	local game = GameHarness.startSession(world, { real = true, config = config })
	local ctx, c = game.ctx, game.ctx.pools.characters[1]
	c.inventory = Inventory.new({ plank = 1000, stone = 1000 })
	local placed = {}
	for i, s in ipairs(STARTERS) do
		local source = assert(love.filesystem.read("content/designs/" .. s.name .. ".lua"))
		placed[i] = assert(Placement.build(ctx, Designs.request(source, "N", s.x, s.y, "e2e_" .. s.name, ctx.config)))
	end
	-- The player off to the side, outside every footprint.
	c.x, c.y = 26.5 * TILE, 15.5 * TILE
	game:mousemoved(5, 5, 0, 0)
	Fake.runUntil(game, function()
		return true
	end, 1)
	c.x, c.y = 26.5 * TILE, 15.5 * TILE
	assertEqual(nil, BuildingsRender.cutawayOf(ctx), "outside, nothing is cut away")

	local p = Projection.new(config)
	game.camera.zoom = 2
	for _, row in ipairs({ { "north_row", 12.5, 10 }, { "south_row", 12, 21 } }) do
		game.camera.x, game.camera.y = Projection.worldToScreen(p, row[2], row[3], 0)
		Capture.capture(row[1])
	end

	game.camera.zoom = 4
	for i, s in ipairs(STARTERS) do
		local b = placed[i]
		c.x, c.y = (s.x + s.door) * TILE, (s.y + 1.6) * TILE
		assertEqual(b, BuildingsRender.cutawayOf(ctx), s.name .. " is cut away with the player inside")
		local v = Session.newVillager(100 + i, c.x - 0.3 * TILE, (s.y + 1.3) * TILE, ctx.config)
		table.insert(ctx.pools.villagers, v)
		game.camera.x, game.camera.y = Projection.worldToScreen(p, s.x + b.width / 2, s.y + b.depth / 2, 0)
		Capture.capture(s.name .. "_inside")
		table.remove(ctx.pools.villagers)
	end

	-- The 2:1 dimetric view shows the east walls and their windows too. The
	-- first frame in a new view only says it's baking.
	c.x, c.y = 26.5 * TILE, 15.5 * TILE
	game.flow.world.view = "iso2to1"
	local iso = Projection.new(config, 1, config.views.iso2to1)
	game.camera.zoom = 1.5
	for _, row in ipairs({ { "north_row_iso", 12.5, 10 }, { "south_row_iso", 12, 21 } }) do
		game.camera.x, game.camera.y = Projection.worldToScreen(iso, row[2], row[3], 0)
		Capture.capture(row[1] .. "_baking")
		Capture.capture(row[1])
	end
end)
