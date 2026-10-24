-- The shipped starter content (content/prefabs, content/designs): every
-- file runs in the sandbox and compiles, has the roles its name implies,
-- and every starter building is placeable in a new game.
local Builtins = require("src.game.designs.builtins")
local Library = require("src.game.designs.library")
local Lockcheck = require("src.game.script.lockcheck")
local Compile = require("src.game.buildings.compile")
local Placement = require("src.game.buildings.placement")
local Session = require("src.game.session")
local World = require("src.game.world")
local Config = require("src.game.config")
local library = require("tests.support.builtins")

local STARTER_PREFABS = Builtins.STARTER_PREFABS

-- The abilities, port kinds and storage a starter building must have.
local BUILDINGS = {
	woodcutter = { abilities = { "saw" }, output = 1 },
	quarry = { abilities = { "pickaxe" }, output = 1 },
	sawmill = { abilities = { "sawbench" }, input = 1, output = 1 },
	forager_hut = { abilities = { "forager" }, output = 1 },
	fishing_hut = { abilities = { "fishing" }, output = 1 },
	hunter_lodge = { abilities = { "hunter" }, output = 1 },
	bedhouse = { abilities = { "bed", "bed" } },
	canteen = { abilities = { "canteen" } },
	forester = { abilities = { "planter" } },
}

local function abilities(bp)
	local out = {}
	for i, a in ipairs(bp.roles.abilities) do
		out[i] = a.ability
	end
	table.sort(out)
	return table.concat(out, ",")
end

local function ports(bp, kind)
	local n = 0
	for _, p in ipairs(bp.roles.ports) do
		if p.kind == kind then
			n = n + 1
		end
	end
	return n
end

test("the built-in list names every starter prefab and building, and each is shipped", function()
	assertEqual(9, #STARTER_PREFABS)
	for _, name in ipairs(STARTER_PREFABS) do
		assertTrue(library.prefabs[name], "prefab " .. name)
		assertTrue(Library.builtin("prefabs", name), name .. " is a built-in")
	end
	for name in pairs(BUILDINGS) do
		assertTrue(library.designs[name], "design " .. name)
		assertTrue(Library.builtin("designs", name), name .. " is a built-in")
	end
end)

test("starter prefabs aren't role prefabs: they have no roles and a shape", function()
	for _, name in ipairs(STARTER_PREFABS) do
		local bp, message = Compile.design(library.prefabs[name], name, library, Config)
		assertTrue(bp, name .. ": " .. tostring(message))
		assertEqual(0, #bp.roles.abilities + #bp.roles.ports + bp.roles.storage, name .. " roles")
		assertTrue(bp.width >= 1 and bp.depth >= 1, name .. " has a footprint")
		assertTrue(next(bp.cost) ~= nil, name .. " has a cost")
	end
end)

test("every starter prefab is parametric, and only the fence and arch are procedural", function()
	for _, name in ipairs(STARTER_PREFABS) do
		local result = assert(Lockcheck.check(library.prefabs[name], name))
		assertTrue(#result.params >= 2, name .. " has UI params")
	end
	-- the fence and arch build their parts in loops
	assertTrue(library.prefabs.fence:find("for "), "fence loops")
	assertTrue(library.prefabs.arch:find("for "), "arch loops")
end)

test("changing a param changes a starter prefab's geometry", function()
	local longer = [[return prefab("wall", { params = { length = 4 } })]]
	local shorter = [[return prefab("wall", { params = { length = 2 } })]]
	local a = assert(Compile.design(longer, "a", library, Config))
	local b = assert(Compile.design(shorter, "b", library, Config))
	assertEqual(4, a.width)
	assertEqual(2, b.width)
end)

test("every starter building is declarative: nothing the builder can't rewrite", function()
	for name in pairs(BUILDINGS) do
		local result = assert(Lockcheck.check(library.designs[name], name))
		assertFalse(result.locked, name .. " is declarative")
	end
end)

test("every starter building has the roles its name implies", function()
	for name, want in pairs(BUILDINGS) do
		local bp, message = Compile.design(library.designs[name], name, library, Config)
		assertTrue(bp, name .. ": " .. tostring(message))
		local list = {}
		for i, a in ipairs(want.abilities) do
			list[i] = a
		end
		table.sort(list)
		assertEqual(table.concat(list, ","), abilities(bp), name .. " abilities")
		assertEqual(want.input or 0, ports(bp, "input"), name .. " input ports")
		assertEqual(want.output or 0, ports(bp, "output"), name .. " output ports")
		assertEqual(0, #Compile.problems(bp, Config), name .. " problems")
	end
end)

test("the picker offers every starter building", function()
	local offered = {}
	for _, entry in ipairs(Library.placeable(library, Config)) do
		offered[entry.name] = true
	end
	for name in pairs(BUILDINGS) do
		assertTrue(offered[name], name .. " is offered")
	end
end)

test("the five first-chain starters fit the stockpile together", function()
	local total = {}
	for _, name in ipairs({ "woodcutter", "sawmill", "forester", "fishing_hut", "quarry" }) do
		local bp = assert(Compile.design(library.designs[name], name, library, Config))
		for item, n in pairs(bp.cost) do
			total[item] = (total[item] or 0) + n
		end
	end
	for item, n in pairs(total) do
		assertTrue(n <= (Config.stockpile[item] or 0), item .. " " .. n .. " > " .. tostring(Config.stockpile[item]))
	end
end)

test("every starter building can be placed in a new game, whichever way it faces", function()
	local config = Config
	for name in pairs(BUILDINGS) do
		for _, facing in ipairs(Placement.FACINGS) do
			local ctx = Session.newGame(World.new(40, 40), config, 1, library)
			local bp = assert(Compile.design(library.designs[name], name, library, Config))
			local request = { design = name, blueprint = bp, facing = facing, tileX = 4, tileY = 4 }
			local ok, why = Placement.check(ctx, request)
			assertTrue(ok, name .. " " .. facing .. ": " .. tostring(why))
		end
	end
end)

local WalkGrid = require("src.game.buildings.walk_grid")

-- The runs of open cells round `grid`'s edge, walked clockwise from the
-- north-west corner: { length, ... }. A run crossing the start is joined.
local function edgeRuns(grid)
	local w, d = grid.width, grid.depth
	local ring = {}
	for x = 0, w - 1 do
		ring[#ring + 1] = WalkGrid.open(grid, x, 0)
	end
	for y = 1, d - 1 do
		ring[#ring + 1] = WalkGrid.open(grid, w - 1, y)
	end
	for x = w - 2, 0, -1 do
		ring[#ring + 1] = WalkGrid.open(grid, x, d - 1)
	end
	for y = d - 2, 1, -1 do
		ring[#ring + 1] = WalkGrid.open(grid, 0, y)
	end
	local start
	for i, open in ipairs(ring) do
		if not open then
			start = i
			break
		end
	end
	local runs, n = {}, 0
	if not start then
		return { #ring }
	end
	for k = 1, #ring do
		local open = ring[(start + k - 1) % #ring + 1]
		if open then
			n = n + 1
		elseif n > 0 then
			runs[#runs + 1], n = n, 0
		end
	end
	if n > 0 then
		runs[#runs + 1] = n
	end
	return runs
end

test("every starter building and the storage facility is walled in but for doorways at least a tile wide", function()
	local per = Config.walk.cellsPerTile
	local names = { "storage_facility" }
	for name in pairs(BUILDINGS) do
		names[#names + 1] = name
	end
	for _, name in ipairs(names) do
		local bp = assert(Compile.design(library.designs[name], name, library, Config))
		local runs = edgeRuns(bp.walk)
		assertTrue(#runs >= 1, name .. " has a doorway")
		for _, n in ipairs(runs) do
			assertTrue(n >= per, name .. " doorway " .. n .. " studs wide, under a tile")
			assertTrue(n <= 2 * per, name .. " opening " .. n .. " studs wide: not walled in")
		end
	end
end)

test("no starter building's port sits in front of its doorway", function()
	local per = Config.walk.cellsPerTile
	for name in pairs(BUILDINGS) do
		for _, facing in ipairs(Placement.FACINGS) do
			local world = World.new(20, 20)
			local bp = assert(Compile.design(library.designs[name], name, library, Config))
			local b = { tileX = 8, tileY = 8 }
			local doors = {}
			for _, d in ipairs(World.doorways(world, b, Placement.walkGrid(bp, facing), per)) do
				doors[d.tileX .. "," .. d.tileY] = true
			end
			for _, p in ipairs(Placement.ports(bp, facing, b.tileX, b.tileY)) do
				assertFalse(doors[p.x .. "," .. p.y], name .. " " .. facing .. " port at " .. p.x .. "," .. p.y .. " blocks a doorway")
			end
		end
	end
end)
