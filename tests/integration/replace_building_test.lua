-- Replace… on a building (docs/CONTEXT.md "Replace", ADR 0007) through the
-- real input path: right-click the building, Replace…, pick a design; its
-- ghost sits centred on the old building with its facing, R turns it, a
-- click confirms. The site pays only the missing materials, the old
-- building's stock goes to storage, and villagers build the new one.
local GameHarness = require("tests.support.game_harness")
local LoveMock = require("tests.support.love_mock")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local Storage = require("src.game.components.storage")
local StorageFacility = require("src.game.components.storage_facility")
local DesignStore = require("src.app.design_store")
local Designs = require("tests.support.designs")
local Session = require("src.game.session")
local PickerRender = require("src.app.render.picker")
local WorldScreen = require("src.app.screens.world")

local TILE = Config.tileSize

-- A 2x1 woodcutter: a saw and an output port on its south edge.
local WOODCUTTER = Designs.floor(2, 1, Designs.ability("saw", 0.375, 0.125), Designs.port("output", 1, 1))
-- A bigger 3x2 one, costing more planks.
local BIGCUTTER = Designs.floor(3, 2, Designs.ability("saw", 0.375, 0.125), Designs.port("output", 1.5, 2))

local function write(name, text)
	assert(DesignStore.write(Config.designs, "designs", name, text))
end

-- 20x20 world, character on tile (10, 10) at px (320, 320), the stockpile
-- in a facility on the south-east corner tile, both designs in the
-- library, and a woodcutter built facing E with its footprint (12, 7..8).
local function launch()
	_G.love = LoveMock.new()
	write("woodcutter", WOODCUTTER)
	write("bigcutter", BIGCUTTER)
	local world = World.new(20, 20)
	local game = GameHarness.startSession(world, { storage = Config.stockpile })
	local c = game.ctx.pools.characters[1]
	Fake.pickDesign(game, "woodcutter")
	Fake.tap(game, "r")
	Fake.click(game, 1, 640 + (12.5 * TILE - c.x), 360 + (8 * TILE - c.y))
	Fake.tap(game, "escape")
	GameHarness.completeSites(game)
	local old = assert(game.ctx.pools.buildings[2], "the woodcutter")
	assertEqual(12, old.tileX)
	assertEqual(7, old.tileY)
	return game, c, old
end

-- The screen pixel over world point (wx, wy) in tiles.
local function screenOf(c, wx, wy)
	return 640 + (wx * TILE - c.x), 360 + (wy * TILE - c.y)
end

-- Right-clicks building `b` and clicks the menu's Replace… entry.
local function openReplace(game, c, b)
	local sx, sy = screenOf(c, b.tileX + 0.5, b.tileY + 0.5)
	Fake.click(game, 2, sx, sy)
	local menu = assert(game.flow.world.menu, "the menu opened")
	local rect = assert(PickerRender.menuItem(menu, 2), "a second entry")
	Fake.click(game, 1, rect.x + 5, rect.y + 5)
end

test("Replace… on a building opens the picker; the ghost sits centred on it with its facing", function()
	local game, c, old = launch()
	local screen = game.flow.world
	openReplace(game, c, old)
	assertEqual(nil, screen.menu)
	assertTrue(screen.picker ~= nil, "the picker opened")
	Fake.typeText(game, "big")
	Fake.tap(game, "return")

	assertEqual("bigcutter", screen.placing.design)
	assertEqual(old, screen.placing.replaces)
	assertEqual("E", screen.placing.facing, "the old building's facing")
	-- Facing E the 3x2 design is 2x3; centred on the 1x2 footprint at
	-- (12.5, 8): north-west tile (12, 7) after rounding.
	local ghost = WorldScreen.ghost(screen)
	assertEqual(12, ghost.request.tileX)
	assertEqual(7, ghost.request.tileY)
	assertTrue(ghost.ok, tostring(ghost.reason))
end)

-- Picks `query` in the open picker and confirms the ghost with a click
-- anywhere, after `turns` presses of R.
local function confirm(game, query, turns)
	Fake.typeText(game, query)
	Fake.tap(game, "return")
	for _ = 1, turns do
		Fake.tap(game, "r")
	end
	Fake.click(game, 1, 100, 100)
end

local function addVillagers(game, n)
	for i = 1, n do
		table.insert(game.ctx.pools.villagers, Session.newVillager(i, (14 + i + 0.5) * TILE, 16.5 * TILE, Config))
	end
end

test("R turns the replacement, a click confirms it, the stored logs reach storage and villagers build it", function()
	local game, c, old = launch()
	local facility = game.ctx.pools.buildings[1]
	for _ = 1, 3 do
		Storage.add(old.ports[1].buffer, "log")
	end
	local logs = facility.storage.counts.log or 0
	local planks = StorageFacility.totals(game.ctx).plank

	openReplace(game, c, old)
	confirm(game, "big", 1)

	assertTrue(old.dead, "the old building is gone")
	assertEqual(nil, game.flow.world.placing, "placement mode ends")
	local site = assert(game.ctx.pools.sites[1], "a site")
	assertEqual("bigcutter", site.design)
	assertEqual("S", site.facing)
	assertEqual(11, site.tileX)
	assertEqual(7, site.tileY)
	local missing = Designs.blueprint(BIGCUTTER).cost.plank - Designs.blueprint(WOODCUTTER).cost.plank
	assertEqual(missing, site.cost.plank, "only the missing planks")
	assertEqual(planks - missing, StorageFacility.totals(game.ctx).plank)
	assertEqual(logs + 3, facility.storage.counts.log, "the buffered logs went to storage")

	addVillagers(game, 3)
	Fake.runUntil(game, function()
		return #game.ctx.pools.sites == 0
	end, 60 * 120)
	local b = game.ctx.pools.buildings[2]
	assertEqual("bigcutter", b.design)
	assertEqual("S", b.facing)
	assertEqual(2, #game.ctx.pools.buildings)
	assertEqual(nil, StorageFacility.claimed(game.ctx).plank, "nothing left claimed")
end)

-- Whether any live job holds building `b`: as its building or an end.
local function jobOn(ctx, b)
	for _, job in ipairs(ctx.pools.jobs) do
		if not job.dead and (job.building == b or (job.source and job.source.building == b) or (job.dest and job.dest.building == b)) then
			return job
		end
	end
	return nil
end

-- Every store of every building: { name, store }.
local function stores(ctx)
	local list = {}
	for i, b in ipairs(ctx.pools.buildings) do
		list[#list + 1] = { "building " .. i .. " storage", b.storage }
		for p, port in ipairs(b.ports) do
			list[#list + 1] = { "building " .. i .. " port " .. p, port.buffer }
		end
	end
	return list
end

test("replacing a working woodcutter ends its jobs, leaks no reservation, and every log reaches storage", function()
	local game, c, old = launch()
	local ctx = game.ctx
	local facility = ctx.pools.buildings[1]
	local trees = {}
	for i, y in ipairs({ 4, 5 }) do
		trees[i] = { id = i, kind = "tree", tileX = 11, tileY = y, variant = 1, stage = 1, amount = 3 }
		World.addNode(ctx.world, trees[i])
	end
	local logs = facility.storage.counts.log or 0
	addVillagers(game, 3)
	local saw = old.functionBricks[1]
	Fake.runUntil(game, function()
		return saw.operator ~= nil and saw.node ~= nil
	end, 60 * 60)

	openReplace(game, c, old)
	confirm(game, "big", 0)

	assertTrue(old.dead)
	assertEqual(nil, jobOn(ctx, old), "no job holds the old building")
	assertEqual(nil, saw.operator, "the operator lost its job")
	for _, tree in ipairs(trees) do
		assertTrue(tree.reservedBy ~= saw, "the old saw let go of its tree")
	end
	for _, v in ipairs(ctx.pools.villagers) do
		assertTrue(v.job == nil or not v.job.dead, "no villager holds an ended job")
	end

	Fake.runUntil(game, function()
		return #ctx.pools.sites == 0 and trees[1].dead and trees[2].dead and #ctx.pools.jobs == 0
			and (facility.storage.counts.log or 0) == logs + 6
	end, 60 * 240)
	for _, entry in ipairs(stores(ctx)) do
		local name, store = entry[1], entry[2]
		assertEqual(0, store.incoming or 0, name .. " room reserved")
		assertEqual(nil, next(store.reserved or {}), name .. " items reserved")
		assertEqual(nil, next(store.claimed or {}), name .. " items claimed")
	end
end)

test("a badge shows once the design file changed, and replacing with the same design applies the edit", function()
	local game, c, old = launch()
	local screen = game.flow.world
	assertFalse(WorldScreen.changed(screen, old), "built from the file as it is")

	-- The woodcutter gains a wall; seen once back from the builder.
	local EDITED = Designs.floor(2, 1, Designs.ability("saw", 0.375, 0.125), Designs.port("output", 1, 1), "box{ size = { 0.25, 1, 1 } }")
	write("woodcutter", EDITED)
	Fake.tap(game, "b")
	Fake.tap(game, "escape")
	assertEqual("world", game.flow.screen)
	assertTrue(WorldScreen.changed(screen, old), "the badge shows")

	openReplace(game, c, old)
	confirm(game, "woodcutter", 0)
	GameHarness.completeSites(game)
	local b = game.ctx.pools.buildings[2]
	assertTrue(b ~= old, "a new building")
	assertEqual("woodcutter", b.design)
	assertEqual(Designs.blueprint(EDITED).hash, b.blueprint.hash, "the edit applied")
	assertFalse(WorldScreen.changed(screen, b), "no badge on the new one")
end)
