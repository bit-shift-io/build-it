local Projection = require("src.game.projection")

local CONFIG = { tileSize = 32, projection = { heightScale = 0.75 } }

test("Projection.worldToScreen keeps ground tiles square and lifts height up the screen", function()
	local p = Projection.new(CONFIG)
	local sx, sy = Projection.worldToScreen(p, 3, 2, 0)
	assertNear(96, sx)
	assertNear(64, sy)

	sx, sy = Projection.worldToScreen(p, 3, 2, 1)
	assertNear(96, sx)
	assertNear(64 - 0.75 * 32, sy)
end)

test("Projection.screenToWorld round-trips worldToScreen at a given height", function()
	local p = Projection.new(CONFIG, 3)
	for _, pt in ipairs({ { 0, 0, 0 }, { 1.25, 7.5, 0 }, { 4, 2, 1.5 }, { -2, 3, 0.25 } }) do
		local sx, sy = Projection.worldToScreen(p, pt[1], pt[2], pt[3])
		local x, y = Projection.screenToWorld(p, sx, sy, pt[3])
		assertNear(pt[1], x)
		assertNear(pt[2], y)
	end
end)

test("Projection.depth grows toward the viewer: further south and higher are nearer", function()
	local p = Projection.new(CONFIG)
	assertTrue(Projection.depth(p, 0, 5, 0) > Projection.depth(p, 0, 4, 0), "south is nearer")
	assertTrue(Projection.depth(p, 0, 4, 1) > Projection.depth(p, 0, 4, 0), "higher is nearer")
	assertNear(Projection.depth(p, 0, 4, 0), Projection.depth(p, 9, 4, 0), 0.000001, "east-west does not change depth")
	-- Two points that draw on the same pixel: the higher, more southern one is in front.
	local sx, sy = Projection.worldToScreen(p, 2, 3, 1)
	local gx, gy = Projection.screenToWorld(p, sx, sy, 0)
	assertTrue(Projection.depth(p, 2, 3, 1) > Projection.depth(p, gx, gy, 0))
end)

local function boundsOf(minX, minY, minZ, maxX, maxY, maxZ)
	return { minX = minX, minY = minY, minZ = minZ, maxX = maxX, maxY = maxY, maxZ = maxZ }
end

test("Projection.spriteFrame sizes a sprite to the projected bounds with an integer anchor at the model origin", function()
	local p = Projection.new(CONFIG)
	local frame = Projection.spriteFrame(p, boundsOf(0, 0, 0, 2, 1, 2))
	assertEqual(64, frame.width)
	assertEqual(32 + 48, frame.height)
	assertEqual(0, frame.anchorX)
	assertEqual(48, frame.anchorY)

	-- A top at 0.1 tiles lifts 2.4 px: the sprite grows to whole pixels.
	local thin = Projection.spriteFrame(p, boundsOf(0.5, 0, 0, 1, 1, 0.1))
	assertEqual(16, thin.width)
	assertEqual(35, thin.height)
	assertEqual(-16, thin.anchorX)
	assertEqual(3, thin.anchorY)
end)

test("Projection.modelToSprite puts the origin on the anchor and round-trips spriteToModel", function()
	local p = Projection.new(CONFIG, 2)
	local frame = Projection.spriteFrame(p, boundsOf(0, 0, 0, 3, 2, 1.5))
	local px, py = Projection.modelToSprite(p, frame, 0, 0, 0)
	assertEqual(frame.anchorX, px)
	assertEqual(frame.anchorY, py)

	-- The bounds' far corners land on the sprite's edges.
	px, py = Projection.modelToSprite(p, frame, 3, 0, 1.5)
	assertNear(frame.width, px)
	assertNear(0, py)
	px, py = Projection.modelToSprite(p, frame, 0, 2, 0)
	assertNear(0, px)
	assertNear(frame.height, py)

	for _, pt in ipairs({ { 1, 1, 0.5 }, { 2.75, 0.25, 1.5 }, { 0, 2, 0 } }) do
		local sx, sy = Projection.modelToSprite(p, frame, pt[1], pt[2], pt[3])
		local x, y = Projection.spriteToModel(p, frame, sx, sy, pt[3])
		assertNear(pt[1], x)
		assertNear(pt[2], y)
	end
end)

test("Projection.placeSprite lands the footprint exactly on its tiles at every bake scale", function()
	local world = Projection.new(CONFIG)
	local bounds = boundsOf(0, 0, 0, 3, 2, 2.75)
	for scale = 1, 4 do
		local baked = Projection.new(CONFIG, scale)
		local frame = Projection.spriteFrame(baked, bounds)
		local left, top, drawScale = Projection.placeSprite(world, frame, 7, 5)
		assertNear(1 / scale, drawScale)

		-- Footprint corners: north-west (0, 0) and south-east (3, 2) at ground level.
		for _, corner in ipairs({ { 0, 0 }, { 3, 2 } }) do
			local px, py = Projection.modelToSprite(baked, frame, corner[1], corner[2], 0)
			local wantX, wantY = Projection.worldToScreen(world, 7 + corner[1], 5 + corner[2], 0)
			assertNear(wantX, left + px * drawScale, 0.000001, "scale " .. scale)
			assertNear(wantY, top + py * drawScale, 0.000001, "scale " .. scale)
		end
	end
end)

test("Projection.bakeScale is the smallest whole scale at or above the zoom", function()
	assertEqual(1, Projection.bakeScale(0.25))
	assertEqual(1, Projection.bakeScale(1))
	assertEqual(2, Projection.bakeScale(1.1))
	assertEqual(2, Projection.bakeScale(2))
	assertEqual(4, Projection.bakeScale(3.5))
end)
