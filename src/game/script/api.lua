-- The functions a design script sees (docs/CONTEXT.md "Design script",
-- "Node", "Param"; ADR 0006). Every function here is reachable from an
-- untrusted script: each one is a review point.
--
-- Node calls build plain tables:
--   box{ id, name, size = { w, d, h }, transform }      corner at the origin
--   sphere{ id, name, radius, segments, transform }     centred on the origin
--   cylinder{ id, name, radius, height, segments, transform }
--   cone{ id, name, radius, height, segments, transform }
--                                                       base centred on the
--                                                       origin, up to height
--   wedge{ id, name, size = { w, d, h }, transform }    a box from the origin
--                                                       sloping from h on its
--                                                       west face to 0 at east
-- segments: a whole number, Api.SEGMENTS.min to .max (default 24).
--   group{ id, name, transform, <child>, <child>, ... }
--   role{ id, name, transform, ability = "saw" | port = "input"|"output" |
--         storage = n }                                 a role at its origin
--   prefab("name", { id, name, transform, params = { width = 2 } })
--                                                       a library prefab,
--                                                       resolved after the
--                                                       run; params override
--                                                       its UI.* params by
--                                                       name
--   shape{ id, name, transform, points = { { x, y }, { x, y, hx, hy }, ... },
--          plane = { origin = { x, y, z }, u = { x, y, z }, v = { x, y, z } } }
--                                                       a closed 2D outline
--                                                       on a work plane (the
--                                                       ground by default),
--                                                       no volume; points as
--                                                       src/game/geometry/shape2d.lua
--   extrude{ id, name, transform, height, shape{ ... } }
--   lathe{ id, name, transform, angle = 360, segments = 24, shape{ ... } }
--                                                       its one shape pushed
--                                                       height tiles (> 0)
--                                                       along the plane
--                                                       normal u x v: a solid
--   path{ id, name, transform, curve, plane, ... }    an open curve on a
--                                                       work plane, no
--                                                       volume; curve and
--                                                       fields as
--                                                       src/game/geometry/path.lua
--                                                       (default polyline;
--                                                       arc: centre {0,0},
--                                                       radius 1, start 0,
--                                                       angle 90; helix:
--                                                       centre, radius 1,
--                                                       turns 1, pitch 1)
--   sweep{ id, name, transform, twist, startScale, endScale, shape{ ... },
--          path{ ... } }                                its shape carried
--                                                       along its path: a
--                                                       solid; twist in
--                                                       degrees (0), scales
--                                                       above 0 (1)
-- transform = { move = { x, y, z }, rotate = { x, y, z } (degrees),
--               scale = { x, y, z } or one number }, every part optional.
-- Lengths are in tiles; x east, y south, z up.
-- Any node may also take
--   material = { name = "plank" | "stone", variant, scale = 1, rotation = 0 }
-- (config.materials; variant defaults to the material's first): what it and
-- every node under it without its own is made of, and how its texture
-- variant is drawn, scaled (above 0) and turned (degrees), and
--   color = { r, g, b } (channels 0 to 1) or a team slot name
-- (src/game/palette.lua's Palette.SLOTS, e.g. "primary"): the colour it and
-- every node under it without its own is painted, tinting its texture. A
-- slot resolves to the owner's team palette at bake.
--
-- Params (src/game/script/params.lua) are declared with a table and return
-- their value, the default clamped to its range:
--   UI.number{ label, default (min or 0), step, min, max }
--   UI.bool{ label, default (false) }
--   UI.choice{ label, options = { "a", "b" }, default (the first option) }
--   UI.color{ label, default = { r, g, b } (white), channels 0 to 1 }
local Params = require("src.game.script.params")
local Shape2d = require("src.game.geometry.shape2d")
local Path = require("src.game.geometry.path")
local Palette = require("src.game.palette")
-- Only the material catalogue (config.materials) is read: it is the same
-- in every config.
local MATERIALS = require("src.game.config").materials

local Api = {}

-- Raises `message` with no position; exposed() adds the script's line.
local function fail(message)
	error(message, 0)
end

-- `fn` as the script sees it: its errors point at the calling script line.
local function exposed(fn)
	return function(...)
		local ok, result = pcall(fn, ...)
		if not ok then
			error(result, 2)
		end
		return result
	end
end

local function vector(value, field, kind)
	if value == nil then
		return nil
	end
	if type(value) ~= "table" then
		fail(kind .. " " .. field .. " must be a table of 3 numbers")
	end
	local out = {}
	for i = 1, 3 do
		if type(value[i]) ~= "number" then
			fail(kind .. " " .. field .. " must be a table of 3 numbers")
		end
		out[i] = value[i]
	end
	return out
end

local function transform(value, kind)
	if value == nil then
		return {}
	end
	if type(value) ~= "table" then
		fail(kind .. " transform must be a table")
	end
	local scale = value.scale
	if type(scale) == "number" then
		scale = { scale, scale, scale }
	end
	return {
		move = vector(value.move, "transform.move", kind),
		rotate = vector(value.rotate, "transform.rotate", kind),
		scale = vector(scale, "transform.scale", kind),
	}
end

local function text(value, field, kind)
	if value ~= nil and type(value) ~= "string" then
		fail(kind .. " " .. field .. " must be a string")
	end
	return value
end

local function positive(value, field, kind)
	if value ~= nil and (type(value) ~= "number" or not (value > 0)) then
		fail(kind .. " " .. field .. " must be a number above 0")
	end
	return value
end

-- How many sides round a curved primitive is cut into. Capped: the mesh is
-- built outside the sandbox's budget, so a huge count would hang the game.
Api.SEGMENTS = { default = 24, min = 3, max = 64 }

local function segments(value, kind)
	if value == nil then
		return Api.SEGMENTS.default
	end
	if type(value) ~= "number" or value % 1 ~= 0 or value < Api.SEGMENTS.min or value > Api.SEGMENTS.max then
		fail(kind .. " segments must be a whole number from " .. Api.SEGMENTS.min .. " to " .. Api.SEGMENTS.max)
	end
	return value
end

-- The most points a shape may have: its outline is checked outside the
-- sandbox's budget.
Api.SHAPE_POINTS = 256

local function shapePoints(value)
	if type(value) ~= "table" then
		fail("shape points must be a list of points, e.g. { { 0, 0 }, { 1, 0 }, { 1, 1 } }")
	end
	if #value > Api.SHAPE_POINTS then
		fail("shape has more than " .. Api.SHAPE_POINTS .. " points")
	end
	local out = {}
	for i, p in ipairs(value) do
		local n = type(p) == "table" and #p or 0
		local ok = n == 2 or n == 4
		for k = 1, n do
			ok = ok and type(p[k]) == "number"
		end
		if not ok then
			fail("shape point " .. i .. " must be 2 or 4 numbers: { x, y } or { x, y, hx, hy }")
		end
		out[i] = { unpack(p, 1, n) }
	end
	local _, why = Shape2d.outline(out)
	if why then
		fail("shape " .. why)
	end
	return out
end

-- A shape's or path's (`kind`) plane: the ground unless given, every part
-- optional.
local function shapePlane(value, kind)
	kind = kind or "shape"
	if value ~= nil and type(value) ~= "table" then
		fail(kind .. " plane must be a table")
	end
	value = value or {}
	local plane = {
		origin = vector(value.origin, "plane.origin", kind) or { 0, 0, 0 },
		u = vector(value.u, "plane.u", kind) or { 1, 0, 0 },
		v = vector(value.v, "plane.v", kind) or { 0, 1, 0 },
	}
	local u, v = plane.u, plane.v
	local nx, ny, nz = u[2] * v[3] - u[3] * v[2], u[3] * v[1] - u[1] * v[3], u[1] * v[2] - u[2] * v[1]
	if nx == 0 and ny == 0 and nz == 0 then
		fail(kind .. " plane u and v must not be parallel")
	end
	return plane
end

-- The most turns a helix may make: its points are built outside the
-- sandbox's budget.
Api.HELIX_TURNS = 16

local function number(value, field, kind)
	if value ~= nil and (type(value) ~= "number" or value ~= value or math.abs(value) == math.huge) then
		fail(kind .. " " .. field .. " must be a number")
	end
	return value
end

local function pair(value, field, kind)
	if value == nil then
		return nil
	end
	if type(value) ~= "table" or type(value[1]) ~= "number" or type(value[2]) ~= "number" or value[3] ~= nil then
		fail(kind .. " " .. field .. " must be 2 numbers, e.g. { 0, 0 }")
	end
	return { value[1], value[2] }
end

-- A point path's points: 2 numbers each, or 4 on a Bézier (as a shape's),
-- exactly 2 points on a line, and not all in one spot.
local function pathPoints(value, curve)
	if type(value) ~= "table" then
		fail("path points must be a list of points, e.g. { { 0, 0 }, { 1, 0 } }")
	end
	if #value > Api.SHAPE_POINTS then
		fail("path has more than " .. Api.SHAPE_POINTS .. " points")
	end
	local out = {}
	for i, p in ipairs(value) do
		local n = type(p) == "table" and #p or 0
		local ok = n == 2 or (n == 4 and curve == "bezier")
		for k = 1, n do
			ok = ok and type(p[k]) == "number"
		end
		if not ok then
			fail("path point " .. i .. (curve == "bezier" and " must be 2 or 4 numbers" or " must be 2 numbers"))
		end
		out[i] = { unpack(p, 1, n) }
	end
	if curve == "line" and #out ~= 2 then
		fail("a line path needs exactly 2 points")
	end
	for i = 2, #out do
		if out[i][1] ~= out[1][1] or out[i][2] ~= out[1][2] then
			return out
		end
	end
	fail("path needs at least 2 different points")
end

-- A path's fields beyond its plane, by curve (src/game/geometry/path.lua).
local function pathFields(t, curve)
	if curve == "arc" then
		local angle = number(t.angle, "angle", "arc path") or 90
		if angle == 0 or math.abs(angle) > 360 then
			fail("arc path angle must be from -360 to 360 degrees, not 0")
		end
		return {
			centre = pair(t.centre, "centre", "arc path") or { 0, 0 },
			radius = positive(t.radius, "radius", "arc path") or 1,
			start = number(t.start, "start", "arc path") or 0,
			angle = angle,
		}
	elseif curve == "helix" then
		local turns = positive(t.turns, "turns", "helix path") or 1
		if turns > Api.HELIX_TURNS then
			fail("helix path turns must be at most " .. Api.HELIX_TURNS)
		end
		return {
			centre = pair(t.centre, "centre", "helix path") or { 0, 0 },
			radius = positive(t.radius, "radius", "helix path") or 1,
			turns = turns,
			pitch = number(t.pitch, "pitch", "helix path") or 1,
		}
	end
	return { points = pathPoints(t.points, curve) }
end

-- A node's material (config.materials), every part filled in, or nil when
-- not given.
local function material(value, kind)
	if value == nil then
		return nil
	end
	if type(value) ~= "table" then
		fail(kind .. ' material must be a table, e.g. { name = "stone" }')
	end
	local entry = MATERIALS[value.name]
	if not entry then
		local names = {}
		for name in pairs(MATERIALS) do
			names[#names + 1] = name
		end
		table.sort(names)
		fail(kind .. " material name must be one of " .. table.concat(names, ", "))
	end
	local variant = value.variant == nil and entry.variants[1] or value.variant
	local known = false
	for _, v in ipairs(entry.variants) do
		known = known or v == variant
	end
	if not known then
		fail(kind .. " material variant for " .. value.name .. " must be one of " .. table.concat(entry.variants, ", "))
	end
	return {
		name = value.name,
		variant = variant,
		scale = positive(value.scale, "material scale", kind) or 1,
		rotation = number(value.rotation, "material rotation", kind) or 0,
	}
end

-- `value` as a node's material, every part filled in, or nil and why it
-- can't be one.
function Api.material(value)
	local ok, result = pcall(material, value, "node")
	if not ok then
		return nil, result
	end
	return result
end

-- A node's colour: a copy of an { r, g, b } literal or a slot name, or nil
-- when not given.
local function color(value, kind)
	if value == nil then
		return nil
	end
	if type(value) == "string" then
		if not Palette.isSlot(value) then
			fail(kind .. " color slot must be one of " .. table.concat(Palette.SLOTS, ", "))
		end
		return value
	end
	if type(value) ~= "table" then
		fail(kind .. ' color must be { r, g, b } or a slot name, e.g. "primary"')
	end
	local out = vector(value, "color", kind)
	for i = 1, 3 do
		if out[i] < 0 or out[i] > 1 then
			fail(kind .. " color channels must be 0 to 1")
		end
	end
	return out
end

-- A prefab instance's param overrides (docs/CONTEXT.md "Param"): a copy of
-- { [param name] = number | true/false | choice string | { r, g, b } }, or
-- nil when not given. Whether each fits its param is checked when the
-- prefab runs (src/game/script/resolve.lua).
local function overrides(value)
	if value == nil then
		return nil
	end
	if type(value) ~= "table" then
		fail("prefab params must be a table, e.g. { width = 2 }")
	end
	local out = {}
	for name, v in pairs(value) do
		if type(name) ~= "string" then
			fail("prefab params are named, e.g. { width = 2 }")
		end
		local kind = type(v)
		if kind == "table" then
			out[name] = vector(v, "param " .. name, "prefab")
		elseif kind == "number" or kind == "boolean" or kind == "string" then
			out[name] = v
		else
			fail("prefab param " .. name .. " must be a number, true/false, a string or { r, g, b }")
		end
	end
	return out
end

-- `value` as a node's colour (a copy), or nil and why it can't be one.
function Api.color(value)
	if value == nil then
		return nil, "no colour"
	end
	local ok, result = pcall(color, value, "node")
	if not ok then
		return nil, result
	end
	return result
end

-- A fresh API for one run. Returns the functions to expose and the run's
-- state: { params = { <param> (src/game/script/params.lua), ... } } and
-- isNode(t), whether t is a node this API built. `given` (optional) holds
-- values by declaration order, [1] for the first UI.* call: a param with
-- one that fits takes it as its value instead of its default (a prefab
-- instance's override); one that doesn't fit is ignored.
function Api.new(given)
	given = given or {}
	local nodes = setmetatable({}, { __mode = "k" })
	local state = { params = {} }

	local function node(kind, args, extra)
		if type(args) ~= "table" then
			fail(kind .. " takes a table, e.g. " .. kind .. "{ id = \"a\" }")
		end
		local n = {
			kind = kind,
			id = text(args.id, "id", kind),
			name = text(args.name, "name", kind),
			transform = transform(args.transform, kind),
			material = material(args.material, kind),
			color = color(args.color, kind),
		}
		for k, v in pairs(extra) do
			n[k] = v
		end
		nodes[n] = true
		return n
	end

	local functions = {}

	function functions.box(args)
		local size = type(args) == "table" and vector(args.size, "size", "box") or nil
		return node("box", args, { size = size or { 1, 1, 1 } })
	end

	function functions.wedge(args)
		local size = type(args) == "table" and vector(args.size, "size", "wedge") or nil
		return node("wedge", args, { size = size or { 1, 1, 1 } })
	end

	function functions.sphere(args)
		local radius = type(args) == "table" and args.radius or nil
		if radius ~= nil and type(radius) ~= "number" then
			fail("sphere radius must be a number")
		end
		return node("sphere", args, { radius = radius or 0.5, segments = segments(type(args) == "table" and args.segments or nil, "sphere") })
	end

	function functions.cylinder(args)
		local t = type(args) == "table" and args or {}
		return node("cylinder", args, {
			radius = positive(t.radius, "radius", "cylinder") or 0.5,
			height = positive(t.height, "height", "cylinder") or 1,
			segments = segments(t.segments, "cylinder"),
		})
	end

	function functions.cone(args)
		local t = type(args) == "table" and args or {}
		return node("cone", args, {
			radius = positive(t.radius, "radius", "cone") or 0.5,
			height = positive(t.height, "height", "cone") or 1,
			segments = segments(t.segments, "cone"),
		})
	end

	function functions.group(args)
		local children = {}
		if type(args) == "table" then
			for i, child in ipairs(args) do
				if not nodes[child] then
					fail("group child " .. i .. " is not a node")
				end
				children[i] = child
			end
		end
		return node("group", args, { children = children })
	end

	-- A shape (docs/CONTEXT.md "Shape"): points in its plane's 2D
	-- coordinates, the plane kept beside them so operations know its axis.
	function functions.shape(args)
		local t = type(args) == "table" and args or {}
		return node("shape", args, { points = shapePoints(t.points), plane = shapePlane(t.plane) })
	end

	-- An extrude (docs/CONTEXT.md "Operation"): the one shape child pushed
	-- `height` along its plane's normal.
	function functions.extrude(args)
		local t = type(args) == "table" and args or {}
		if t.height == nil then
			fail("extrude needs a height, e.g. extrude{ height = 1, shape{ ... } }")
		end
		local height = positive(t.height, "height", "extrude")
		local shape = t[1]
		if not nodes[shape] or shape.kind ~= "shape" or t[2] ~= nil then
			fail("extrude needs exactly one shape inside it")
		end
		return node("extrude", args, { height = height, children = { shape } })
	end

	-- A lathe (docs/CONTEXT.md "Operation"): the one shape child revolved
	-- `angle` degrees (default 360) about its plane's v axis in `segments`
	-- steps.
	function functions.lathe(args)
		local t = type(args) == "table" and args or {}
		local angle = number(t.angle, "angle", "lathe") or 360
		if angle == 0 or math.abs(angle) > 360 then
			fail("lathe angle must be from -360 to 360 degrees, not 0")
		end
		local shape = t[1]
		if not nodes[shape] or shape.kind ~= "shape" or t[2] ~= nil then
			fail("lathe needs exactly one shape inside it")
		end
		return node("lathe", args, { angle = angle, segments = segments(t.segments, "lathe"), children = { shape } })
	end

	-- A path (docs/CONTEXT.md "Path"): an open curve on a work plane that
	-- a sweep carries its shape along.
	function functions.path(args)
		local t = type(args) == "table" and args or {}
		local curve = t.curve == nil and "polyline" or t.curve
		if not Path.CURVES[curve] then
			fail("path curve must be one of " .. table.concat(Path.CURVE_NAMES, ", "))
		end
		local extra = pathFields(t, curve)
		extra.curve, extra.plane = curve, shapePlane(t.plane, "path")
		return node("path", args, extra)
	end

	-- A sweep (docs/CONTEXT.md "Operation"): its shape carried along its
	-- path, turned `twist` degrees and scaled from startScale to endScale
	-- on the way.
	function functions.sweep(args)
		local t = type(args) == "table" and args or {}
		local shape, path = t[1], t[2]
		if not (nodes[shape] and shape.kind == "shape" and nodes[path] and path.kind == "path") or t[3] ~= nil then
			fail("sweep needs a shape and then a path inside it")
		end
		return node("sweep", args, {
			twist = number(t.twist, "twist", "sweep") or 0,
			startScale = positive(t.startScale, "startScale", "sweep") or 1,
			endScale = positive(t.endScale, "endScale", "sweep") or 1,
			children = { shape, path },
		})
	end

	-- A role marker (docs/CONTEXT.md "Role prefab"): what the building gets
	-- where the node sits. Exactly one of ability (a function brick's
	-- ability name), port ("input" | "output") or storage (items, > 0).
	function functions.role(args)
		if type(args) ~= "table" then
			fail("role takes a table, e.g. role{ ability = \"saw\" }")
		end
		local role, given = {}, 0
		if args.ability ~= nil then
			if type(args.ability) ~= "string" then
				fail("role ability must be a string")
			end
			role.ability, given = args.ability, given + 1
		end
		if args.port ~= nil then
			if args.port ~= "input" and args.port ~= "output" then
				fail("role port must be \"input\" or \"output\"")
			end
			role.port, given = args.port, given + 1
		end
		if args.storage ~= nil then
			if type(args.storage) ~= "number" or args.storage <= 0 then
				fail("role storage must be a number above 0")
			end
			role.storage, given = args.storage, given + 1
		end
		if given ~= 1 then
			fail("role needs exactly one of ability, port or storage")
		end
		return node("role", args, { role = role })
	end

	-- An instance of the library prefab called `name` (docs/CONTEXT.md
	-- "Prefab"). Only the name is kept: the prefab's script runs later,
	-- when src/game/script/resolve.lua looks it up. Never a path.
	function functions.prefab(name, args)
		if type(name) ~= "string" then
			fail("prefab takes a name, e.g. prefab(\"bed\")")
		end
		local params = overrides(type(args) == "table" and args.params or nil)
		return node("prefab", args or {}, { prefab = name, params = params, children = {} })
	end

	-- Declares a param of `kind` from `args`, with `fields` (field ->
	-- checker) beyond label and default, and returns its value.
	local function declare(kind, args, example, fields, default)
		local call = "UI." .. kind
		if type(args) ~= "table" then
			fail(call .. " takes a table, e.g. " .. call .. "(" .. example .. ")")
		end
		local param = { kind = kind, label = text(args.label, "label", call) }
		for field, check in pairs(fields) do
			param[field] = check(args[field], call .. " " .. field)
		end
		local value = args.default
		if value == nil then
			value = default(param)
		end
		local clamped, why = Params.clamp(param, value)
		if clamped == nil then
			fail(call .. " default " .. why)
		end
		param.default, param.value = clamped, clamped
		local override = given[#state.params + 1]
		if override ~= nil then
			local fits = Params.clamp(param, override)
			if fits ~= nil then
				clamped, param.value = fits, fits
			end
		end
		table.insert(state.params, param)
		return type(clamped) == "table" and { clamped[1], clamped[2], clamped[3] } or clamped
	end

	local function optionalNumber(v, what)
		if v ~= nil and type(v) ~= "number" then
			fail(what .. " must be a number")
		end
		return v
	end

	local function options(v, what)
		if type(v) ~= "table" or #v == 0 then
			fail(what .. " must be a list of strings")
		end
		local out = {}
		for i, option in ipairs(v) do
			if type(option) ~= "string" then
				fail(what .. " must be a list of strings")
			end
			out[i] = option
		end
		return out
	end

	local NUMBER = { step = optionalNumber, min = optionalNumber, max = optionalNumber }

	functions.UI = {
		number = function(args)
			return declare("number", args, "{ default = 1 }", NUMBER, function(p)
				return p.min or 0
			end)
		end,
		bool = function(args)
			return declare("bool", args, "{ default = true }", {}, function()
				return false
			end)
		end,
		choice = function(args)
			return declare("choice", args, '{ options = { "a", "b" } }', { options = options }, function(p)
				return p.options[1]
			end)
		end,
		color = function(args)
			return declare("color", args, "{ default = { 1, 0, 0 } }", {}, function()
				return { 1, 1, 1 }
			end)
		end,
	}

	for name, fn in pairs(functions) do
		if type(fn) == "function" then
			functions[name] = exposed(fn)
		end
	end
	for name, fn in pairs(functions.UI) do
		functions.UI[name] = exposed(fn)
	end

	function state.isNode(t)
		return nodes[t] == true
	end

	return functions, state
end

return Api
