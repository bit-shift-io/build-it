local Vec2 = require("src.core.vec2")

test("Vec2.add sums two vectors component-wise", function()
	local result = Vec2.add({ x = 1, y = 2 }, { x = 3, y = 4 })
	assertNear(4, result.x)
	assertNear(6, result.y)
end)

test("Vec2.sub subtracts two vectors component-wise", function()
	local result = Vec2.sub({ x = 5, y = 7 }, { x = 2, y = 3 })
	assertNear(3, result.x)
	assertNear(4, result.y)
end)

test("Vec2.scale multiplies both components by a scalar", function()
	local result = Vec2.scale({ x = 2, y = -3 }, 2)
	assertNear(4, result.x)
	assertNear(-6, result.y)
end)

test("Vec2.dot returns the scalar dot product", function()
	assertNear(11, Vec2.dot({ x = 1, y = 2 }, { x = 3, y = 4 }))
end)

test("Vec2.cross returns the scalar z-component of the 3D cross product", function()
	assertNear(-2, Vec2.cross({ x = 1, y = 2 }, { x = 3, y = 4 }))
end)

test("Vec2.length returns the vector's magnitude", function()
	assertNear(5, Vec2.length({ x = 3, y = 4 }))
end)

test("Vec2.normalize returns a unit vector in the same direction", function()
	local result = Vec2.normalize({ x = 3, y = 4 })
	assertNear(0.6, result.x)
	assertNear(0.8, result.y)
end)

test("Vec2.normalize returns the zero vector for a zero-length input", function()
	local result = Vec2.normalize({ x = 0, y = 0 })
	assertNear(0, result.x)
	assertNear(0, result.y)
end)

test("Vec2.rotate rotates a vector by a right angle", function()
	local result = Vec2.rotate({ x = 1, y = 0 }, math.pi / 2)
	assertNear(0, result.x, 0.0001)
	assertNear(1, result.y, 0.0001)
end)

test("Vec2.perp returns a vector perpendicular to the input", function()
	local a = { x = 3, y = 4 }
	local perp = Vec2.perp(a)
	assertNear(0, Vec2.dot(a, perp), 0.0001)
end)
