local Pick = require("src.game.builder.pick")
local Draft = require("src.game.builder.draft")
local Config = require("src.game.config")

local CFG = Config.builder
local DOWN = { 0, 0, -1 }

local function draft2x2()
	local d = Draft.new()
	Draft.resize(d, 2, 2, CFG)
	return d
end

test("a ray onto the baseplate places a brick on the nearest studs under it", function()
	local hit = Pick.cast(draft2x2(), { 3.3, 2.7, 20 }, DOWN, CFG)
	assertTrue(hit, "expected the ray to hit the baseplate")
	assertEqual(nil, hit.brick)
	assertEqual(2, hit.place.x)
	assertEqual(2, hit.place.y)
	assertEqual(0, hit.place.z)
end)

test("a ray onto a brick top hits that brick and stacks the new brick on it", function()
	local d = draft2x2()
	local below = Draft.place(d, 2, 2, 0, CFG)
	local hit = Pick.cast(d, { 3.6, 3.4, 20 }, DOWN, CFG)
	assertEqual(below, hit.brick)
	assertEqual(3, hit.place.x)
	assertEqual(2, hit.place.y)
	assertEqual(1, hit.place.z)
end)

test("a ray onto a brick's east side places the new brick flush east of it", function()
	local d = draft2x2()
	local brick = Draft.place(d, 0, 2, 1, CFG)
	-- From the east, level with layer 1, slightly south of the brick's middle.
	local hit = Pick.cast(d, { 20, 3.4, 1.5 }, { -1, 0, 0 }, CFG)
	assertEqual(brick, hit.brick)
	assertEqual(2, hit.place.x)
	assertEqual(2, hit.place.y)
	assertEqual(1, hit.place.z)
end)

test("a ray onto a brick's west side places the new brick flush west of it", function()
	local d = draft2x2()
	Draft.place(d, 4, 0, 0, CFG)
	local hit = Pick.cast(d, { -20, 1, 0.5 }, { 1, 0, 0 }, CFG)
	assertEqual(2, hit.place.x)
	assertEqual(0, hit.place.y)
end)

test("a ray onto a brick's north side places the new brick flush north of it", function()
	local d = draft2x2()
	Draft.place(d, 2, 4, 0, CFG)
	local hit = Pick.cast(d, { 3, -20, 0.5 }, { 0, 1, 0 }, CFG)
	assertEqual(2, hit.place.x)
	assertEqual(2, hit.place.y)
	assertEqual(0, hit.place.z)
end)

test("the nearest brick along the ray wins over one behind it", function()
	local d = draft2x2()
	-- Placed top first, so the hit can't just be the last brick checked.
	local top = Draft.place(d, 0, 0, 1, CFG)
	Draft.place(d, 0, 0, 0, CFG)
	local hit = Pick.cast(d, { 1, 1, 20 }, DOWN, CFG)
	assertEqual(top, hit.brick)
	assertEqual(2, hit.place.z)
end)

test("on an edge stud the new brick stays on the baseplate", function()
	local hit = Pick.cast(draft2x2(), { 7.8, 0.2, 20 }, DOWN, CFG)
	assertEqual(6, hit.place.x)
	assertEqual(0, hit.place.y)
end)

test("a slanted ray finds the same baseplate studs as a straight one", function()
	-- Aimed at (3.3, 2.7, 0) from above and to the south.
	local hit = Pick.cast(draft2x2(), { 3.3, 12.7, 10 }, { 0, -1, -1 }, CFG)
	assertEqual(2, hit.place.x)
	assertEqual(2, hit.place.y)
	assertEqual(0, hit.place.z)
end)

test("a ray that misses the baseplate hits nothing", function()
	assertEqual(nil, Pick.cast(draft2x2(), { 20, 20, 20 }, DOWN, CFG))
	assertEqual(nil, Pick.cast(draft2x2(), { 3, 3, 20 }, { 0, 0, 1 }, CFG))
end)

test("a ray onto the seam between two brick tops stacks on top, not beside", function()
	local d = draft2x2()
	Draft.place(d, 0, 0, 0, CFG)
	Draft.place(d, 2, 0, 0, CFG)
	-- Down and west onto the top edge the two bricks share, at x = 2.
	local hit = Pick.cast(d, { 12, 1, 11 }, { -1, 0, -1 }, CFG)
	assertEqual(1, hit.place.z)
	assertEqual(1, hit.place.x)
end)

test("the held brick's turned footprint centres on the hit and stays on the baseplate", function()
	local held = { shape = "1x4", rotation = 1, material = "plank", paint = 1 } -- 1 wide, 4 deep
	local hit = Pick.cast(draft2x2(), { 3.3, 2.7, 20 }, DOWN, CFG, held)
	assertEqual(3, hit.place.x)
	assertEqual(1, hit.place.y)
	hit = Pick.cast(draft2x2(), { 7.5, 7.5, 20 }, DOWN, CFG, held)
	assertEqual(7, hit.place.x)
	assertEqual(4, hit.place.y)
end)
