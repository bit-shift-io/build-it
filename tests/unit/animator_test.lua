local Animator = require("src.game.components.animator")
local Character = require("src.game.props.character")

local CFG = { walkFrameDistance = 10 }

local function directionName(index)
	return Character.DIRECTIONS[index].name
end

test("Animator.direction maps a velocity to one of 8 directions", function()
	local cases = {
		{ 0, -1, "N" },
		{ 1, -1, "NE" },
		{ 1, 0, "E" },
		{ 1, 1, "SE" },
		{ 0, 1, "S" },
		{ -1, 1, "SW" },
		{ -1, 0, "W" },
		{ -1, -1, "NW" },
		-- Nearest of the 8 for in-between angles.
		{ 3, -0.5, "E" },
		{ 0.4, 2, "S" },
	}
	for _, c in ipairs(cases) do
		assertEqual(c[3], directionName(Animator.direction(c[1], c[2])), "velocity " .. c[1] .. "," .. c[2])
	end
end)

test("a new animator stands on the idle frame facing south", function()
	local a = Animator.new()
	assertEqual(Character.IDLE, a.frame)
	assertEqual("S", directionName(a.facing))
end)

test("walking steps through the walk frames, one per walkFrameDistance", function()
	local a = Animator.new()
	local seen = {}
	for _ = 1, 8 do
		Animator.update(a, 10, 0, CFG) -- one walk frame's distance per step
		seen[#seen + 1] = a.frame
	end
	assertEqual(table.concat(Character.WALK, ",") .. "," .. table.concat(Character.WALK, ","), table.concat(seen, ","))
	assertEqual("E", directionName(a.facing))
end)

test("short steps hold a walk frame until walkFrameDistance is covered", function()
	local a = Animator.new()
	Animator.update(a, 0, 4, CFG)
	local first = a.frame
	Animator.update(a, 0, 4, CFG)
	assertEqual(first, a.frame)
	Animator.update(a, 0, 4, CFG)
	assertEqual(Character.WALK[2], a.frame)
end)

test("standing still shows the idle frame and keeps the last facing", function()
	local a = Animator.new()
	Animator.update(a, -3, -3, CFG)
	Animator.update(a, 0, 0, CFG)
	assertEqual(Character.IDLE, a.frame)
	assertEqual("NW", directionName(a.facing))
	-- The walk cycle restarts from its first frame.
	Animator.update(a, -3, 0, CFG)
	assertEqual(Character.WALK[1], a.frame)
	assertEqual("W", directionName(a.facing))
end)

test("a session's character faces where it walks, animates, and idles when it stops", function()
	local Session = require("src.game.session")
	local Config = require("src.game.config")
	local ctx = Session.new({ width = 20, height = 20 }, Config, 1)
	local c = ctx.pools.characters[1]
	assertEqual(Character.IDLE, c.animator.frame)

	local frames = {}
	ctx.intents[1] = { x = 1, y = 1 }
	for _ = 1, 60 do
		Session.advance(ctx, 1 / 60)
		frames[c.animator.frame] = true
	end
	assertEqual("SE", directionName(c.animator.facing))
	for _, f in ipairs(Character.WALK) do
		assertTrue(frames[f], "expected walk frame " .. f .. " within a second of walking")
	end

	ctx.intents[1] = { x = 0, y = 0 }
	Session.advance(ctx, 1 / 60)
	assertEqual(Character.IDLE, c.animator.frame)
	assertEqual("SE", directionName(c.animator.facing))
end)
