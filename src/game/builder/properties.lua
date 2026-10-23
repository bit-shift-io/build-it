-- A node's editable properties (docs/CONTEXT.md "Node"): a primitive's
-- dimensions and segments, an extrude's height, a sweep's twist and
-- scales and an arc's or helix's params, as the builder's properties strip
-- shows them for the selected node. Pure; plain LuaJIT.
--
--   property = { key, label, value, whole (true: a whole number) }
local Api = require("src.game.script.api")
local Scene = require("src.game.builder.scene")

local Properties = {}

-- Where each key lives on a node: field and, for a vector, its index.
local SIZE = {
	{ key = "width", label = "W", field = "size", index = 1 },
	{ key = "depth", label = "D", field = "size", index = 2 },
	{ key = "height", label = "H", field = "size", index = 3 },
}
local RADIUS = { key = "radius", label = "Radius", field = "radius" }
local HEIGHT = { key = "height", label = "Height", field = "height" }
local SEGMENTS = { key = "segments", label = "Segments", field = "segments", whole = true }

-- Any number, below 0 too.
local function anyNumber()
	return nil
end
local TWIST = { key = "twist", label = "Twist", field = "twist", check = anyNumber }
local START_SCALE = { key = "startScale", label = "Start scale", field = "startScale" }
local END_SCALE = { key = "endScale", label = "End scale", field = "endScale" }
local START = { key = "start", label = "Start", field = "start", check = anyNumber }
local ANGLE = {
	key = "angle",
	label = "Angle",
	field = "angle",
	check = function(value)
		if value == 0 or math.abs(value) > 360 then
			return "angle must be from -360 to 360 degrees, not 0"
		end
	end,
}
local TURNS = {
	key = "turns",
	label = "Turns",
	field = "turns",
	check = function(value)
		if not (value > 0 and value <= Api.HELIX_TURNS) then
			return "turns must be above 0 and at most " .. Api.HELIX_TURNS
		end
	end,
}
local PITCH = { key = "pitch", label = "Pitch", field = "pitch", check = anyNumber }

-- A path's properties by its curve: only arcs and helixes have any.
local BY_CURVE = {
	arc = { RADIUS, START, ANGLE },
	helix = { RADIUS, TURNS, PITCH },
}

local BY_KIND = {
	box = SIZE,
	wedge = SIZE,
	sphere = { RADIUS, SEGMENTS },
	cylinder = { RADIUS, HEIGHT, SEGMENTS },
	cone = { RADIUS, HEIGHT, SEGMENTS },
	extrude = { HEIGHT },
	lathe = { ANGLE, SEGMENTS },
	sweep = { TWIST, START_SCALE, END_SCALE },
}

-- The specs of `node`'s properties, in strip order.
local function specs(node)
	if node.kind == "path" then
		return BY_CURVE[node.curve] or {}
	end
	return BY_KIND[node.kind] or {}
end

local function get(node, spec)
	local v = node[spec.field]
	if spec.index then
		return v[spec.index]
	end
	return v
end

-- `node`'s properties, in strip order; none for a node that isn't a
-- primitive.
function Properties.of(node)
	local out = {}
	for i, spec in ipairs(specs(node)) do
		out[i] = { key = spec.key, label = spec.label, value = get(node, spec), whole = spec.whole }
	end
	return out
end

-- Why `value` can't be property `spec`, or nil when it can.
local function problem(spec, value)
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return spec.key .. " must be a number"
	end
	if spec.check then
		return spec.check(value)
	elseif spec.whole then
		local s = Api.SEGMENTS
		if value % 1 ~= 0 or value < s.min or value > s.max then
			return spec.key .. " must be a whole number from " .. s.min .. " to " .. s.max
		end
	elseif not (value > 0 and value < math.huge) then
		return spec.key .. " must be a number above 0"
	end
	return nil
end

-- Sets property `key` of node `id` in `scene` to `value`, a scene edit
-- (History.apply). True when it took; false and why otherwise.
function Properties.set(scene, id, key, value)
	local node = Scene.find(scene, id)
	if not node then
		return false, "no node " .. tostring(id)
	end
	for _, spec in ipairs(specs(node)) do
		if spec.key == key then
			local why = problem(spec, value)
			if why then
				return false, why
			end
			if spec.index then
				node[spec.field][spec.index] = value
			else
				node[spec.field] = value
			end
			return true
		end
	end
	return false, node.kind .. " has no " .. tostring(key)
end

return Properties
