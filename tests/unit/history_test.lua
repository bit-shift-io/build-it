local History = require("src.game.builder.history")
local Draft = require("src.game.builder.draft")
local Config = require("src.game.config")

local CFG = Config.builder

-- The draft's whole state as one comparable string.
local function state(d)
	local parts = { d.width .. "x" .. d.depth }
	for _, b in ipairs(d.bricks) do
		table.insert(
			parts,
			table.concat({ b.x, b.y, b.z, b.width, b.depth, b.shape, b.rotation, b.material, b.paint }, ",")
		)
	end
	return table.concat(parts, "|")
end

local SLOPE = { shape = "slope", rotation = 3, material = "stone", paint = 5 }

test("undo takes back a place and redo puts it back", function()
	local d, h = Draft.new(), History.new()
	local empty = state(d)
	local brick = History.apply(h, d, Draft.place, 0, 0, 0, CFG, SLOPE)
	assertTrue(brick, "expected apply to hand back what place returns")
	local placed = state(d)

	assertTrue(History.undo(h, d))
	assertEqual(empty, state(d))
	assertTrue(History.redo(h, d))
	assertEqual(placed, state(d))
	assertFalse(History.redo(h, d), "expected nothing left to redo")
end)

test("undo and redo step exactly through place, paint, resize and remove", function()
	local d, h = Draft.new(), History.new()
	local states = { state(d) }
	local function step(change, ...)
		assertTrue(History.apply(h, d, change, ...), "expected the change to take")
		table.insert(states, state(d))
	end
	step(Draft.resize, 2, 1, CFG)
	step(Draft.place, 4, 0, 0, CFG, SLOPE)
	step(Draft.place, 0, 0, 0, CFG)
	step(Draft.paint, d.bricks[1], 11)
	step(Draft.resize, 2, 2, CFG)
	step(Draft.remove, d.bricks[2])

	-- A refused change is no step at all.
	assertFalse((History.apply(h, d, Draft.resize, 1, 1, CFG)))
	assertFalse((History.apply(h, d, Draft.paint, d.bricks[1], 11)), "expected repainting the same colour to be no change")

	for i = #states - 1, 1, -1 do
		assertTrue(History.undo(h, d))
		assertEqual(states[i], state(d), "after undoing to step " .. i)
	end
	assertFalse(History.undo(h, d), "expected nothing left to undo")
	for i = 2, #states do
		assertTrue(History.redo(h, d))
		assertEqual(states[i], state(d), "after redoing to step " .. i)
	end
end)

test("a new change after an undo clears the redo", function()
	local d, h = Draft.new(), History.new()
	History.apply(h, d, Draft.place, 0, 0, 0, CFG)
	History.apply(h, d, Draft.place, 2, 0, 0, CFG)
	History.undo(h, d)
	History.apply(h, d, Draft.place, 0, 2, 0, CFG, SLOPE)
	local after = state(d)
	assertFalse(History.redo(h, d), "expected the undone place gone from redo")
	assertEqual(after, state(d))
	assertTrue(History.undo(h, d))
	assertEqual(1, #d.bricks)
end)

test("a refused change after an undo keeps the redo", function()
	local d, h = Draft.new(), History.new()
	History.apply(h, d, Draft.place, 0, 0, 0, CFG)
	History.undo(h, d)
	History.apply(h, d, Draft.place, 3, 3, 0, CFG) -- hangs off the baseplate
	assertTrue(History.redo(h, d))
	assertEqual(1, #d.bricks)
end)
