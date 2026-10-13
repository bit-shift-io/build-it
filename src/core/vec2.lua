-- 2D vector math over plain {x, y} tables. Pure functions only -- no
-- `love.*`, no mutation of inputs -- so src/core stays unit-testable with no
-- `love` global (docs/ARCHITECTURE.md "Layers").
local Vec2 = {}

function Vec2.add(a, b)
	return { x = a.x + b.x, y = a.y + b.y }
end

function Vec2.sub(a, b)
	return { x = a.x - b.x, y = a.y - b.y }
end

function Vec2.scale(a, s)
	return { x = a.x * s, y = a.y * s }
end

function Vec2.dot(a, b)
	return a.x * b.x + a.y * b.y
end

-- The z-component of the 3D cross product of (a.x, a.y, 0) and (b.x, b.y, 0).
-- Its sign tells which side b turns relative to a.
function Vec2.cross(a, b)
	return a.x * b.y - a.y * b.x
end

function Vec2.length(a)
	return math.sqrt(a.x * a.x + a.y * a.y)
end

-- Returns the zero vector for a zero-length input rather than dividing by
-- zero -- callers get a defined (if meaningless) direction instead of NaN.
function Vec2.normalize(a)
	local len = Vec2.length(a)
	if len == 0 then
		return { x = 0, y = 0 }
	end
	return { x = a.x / len, y = a.y / len }
end

-- Rotates `a` by `angle` radians. Y points down (screen and world space), so a
-- positive angle here turns clockwise on screen, not the y-up-CCW convention.
function Vec2.rotate(a, angle)
	local c, s = math.cos(angle), math.sin(angle)
	return { x = a.x * c - a.y * s, y = a.x * s + a.y * c }
end

-- One of the two perpendiculars to `a`: rotating `a` 90 degrees in the same
-- direction Vec2.rotate turns for a positive angle.
function Vec2.perp(a)
	return { x = -a.y, y = a.x }
end

return Vec2
