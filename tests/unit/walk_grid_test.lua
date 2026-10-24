-- The walk grid (src/game/buildings/walk_grid.lua, docs/CONTEXT.md "Walk
-- grid", ADR 0008): a blueprint's stud cells, 4 per tile side, blocked
-- where geometry lies in the body-height band. Built by the real compiler.
local Compile = require("src.game.buildings.compile")
local WalkGrid = require("src.game.buildings.walk_grid")
local Config = require("src.game.config")

local function compile(text)
	local blueprint, message = Compile.design(text, "design", { prefabs = {} }, Config)
	assertTrue(blueprint, message)
	return blueprint
end

-- A 2 x 2 room: a floor, full-height walls one voxel thick, and a gap in
-- the south wall from x = 0.75 to 1.25 (stud cells 3 and 4).
local ROOM = [[
	return group{
		box{ size = { 2, 2, 0.0625 } },
		box{ size = { 2, 0.0625, 1 } },
		box{ size = { 0.0625, 2, 1 } },
		box{ size = { 0.0625, 2, 1 }, transform = { move = { 1.9375, 0, 0 } } },
		box{ size = { 0.75, 0.0625, 1 }, transform = { move = { 0, 1.9375, 0 } } },
		box{ size = { 0.75, 0.0625, 1 }, transform = { move = { 1.25, 1.9375, 0 } } },
	}
]]

test("a room's walk grid is 4 stud cells a tile side", function()
	local walk = compile(ROOM).walk
	assertEqual(8, walk.width)
	assertEqual(8, walk.depth)
end)

test("a room's walls block their cells; inside and the gap stay open", function()
	local walk = compile(ROOM).walk
	for i = 0, 7 do
		assertFalse(WalkGrid.open(walk, i, 0), "north wall cell " .. i)
		assertFalse(WalkGrid.open(walk, 0, i), "west wall cell " .. i)
		assertFalse(WalkGrid.open(walk, 7, i), "east wall cell " .. i)
	end
	for _, i in ipairs({ 0, 1, 2, 5, 6, 7 }) do
		assertFalse(WalkGrid.open(walk, i, 7), "south wall cell " .. i)
	end
	assertTrue(WalkGrid.open(walk, 3, 7), "gap cell 3")
	assertTrue(WalkGrid.open(walk, 4, 7), "gap cell 4")
	for y = 1, 6 do
		for x = 1, 6 do
			assertTrue(WalkGrid.open(walk, x, y), "inside cell " .. x .. "," .. y)
		end
	end
end)

test("a floor slab and a low fence block nothing", function()
	local walk = compile([[
		return group{
			box{ size = { 2, 1, 0.0625 } },
			box{ size = { 2, 0.0625, 0.0625 }, transform = { move = { 0, 0.5, 0.0625 } } },
		}
	]]).walk
	assertEqual(string.rep(".", 8 * 4), walk.cells)
end)

local Blueprint = require("src.game.buildings.blueprint")

test("a blueprint's hash covers its walk grid", function()
	local bp = compile(ROOM)
	local other = {}
	for k, v in pairs(bp) do
		other[k] = v
	end
	other.walk = { width = bp.walk.width, depth = bp.walk.depth, cells = string.rep("x", #bp.walk.cells) }
	assertEqual(bp.hash, Blueprint.hash(bp))
	assertTrue(Blueprint.hash(other) ~= bp.hash, "a different walk grid, a different hash")
end)

local Placement = require("src.game.buildings.placement")

-- The blocked cells of `grid` as "x,y" in row order.
local function blocked(grid)
	local out = {}
	for y = 0, grid.depth - 1 do
		for x = 0, grid.width - 1 do
			if not WalkGrid.open(grid, x, y) then
				out[#out + 1] = x .. "," .. y
			end
		end
	end
	return table.concat(out, " ")
end

test("the walk grid turns with the building's facing, a quarter clockwise each", function()
	-- A 2 x 1 floor with a post on its north-west stud cell.
	local bp = compile([[
		return group{
			box{ size = { 2, 1, 0.0625 } },
			box{ size = { 0.25, 0.25, 1 } },
		}
	]])
	local cases = { N = { 8, 4, "0,0" }, E = { 4, 8, "3,0" }, S = { 8, 4, "7,3" }, W = { 4, 8, "0,7" } }
	for facing, want in pairs(cases) do
		local grid = Placement.walkGrid(bp, facing)
		assertEqual(want[1], grid.width, facing .. " width")
		assertEqual(want[2], grid.depth, facing .. " depth")
		assertEqual(want[3], blocked(grid), facing .. " blocked")
	end
end)
