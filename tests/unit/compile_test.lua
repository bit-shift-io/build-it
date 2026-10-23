-- The compiler (src/game/buildings/compile.lua): a design script, with its
-- prefabs resolved by name (src/game/script/resolve.lua), turned into a
-- blueprint (src/game/buildings/blueprint.lua) -- footprint, roles, cost
-- and traits from voxels.
local Compile = require("src.game.buildings.compile")
local Config = require("src.game.config")

-- The blueprint of design script `text`, prefabs from `prefabs`
-- ({ [name] = text }); fails the test when it doesn't compile.
local function compile(text, prefabs)
	local library = { prefabs = prefabs or {} }
	local blueprint, message = Compile.design(text, "design", library, Config)
	assertTrue(blueprint, message)
	return blueprint
end

test("an ability role sits where its node is, in tile fractions", function()
	local bp = compile([[
		return group{ box{ size = { 2, 2, 1 } },
			role{ ability = "saw", transform = { move = { 0.5, 1.5, 0 } } } }
	]])
	assertEqual(1, #bp.roles.abilities)
	local saw = bp.roles.abilities[1]
	assertEqual("saw", saw.ability)
	assertNear(0.5, saw.x)
	assertNear(1.5, saw.y)
end)

local Mesh = require("src.game.geometry.mesh")

test("model space puts the footprint's north-west corner on the origin", function()
	local bp = compile([[
		return group{ transform = { move = { 1, 2, 0 } },
			box{ size = { 2.5, 1, 1 } },
			role{ ability = "saw", transform = { move = { 0.5, 0.5, 0 } } } }
	]])
	assertEqual(3, bp.width)
	assertEqual(1, bp.depth)
	local b = Mesh.bounds(bp.mesh)
	assertNear(0, b.minX)
	assertNear(0, b.minY)
	assertNear(0.5, bp.roles.abilities[1].x)
	assertNear(0.5, bp.roles.abilities[1].y)
end)

-- A design: a w x d x 1 box with an input port role at (x, y).
local function withPort(w, d, x, y)
	return compile(string.format([[
		return group{ box{ size = { %s, %s, 1 } },
			role{ port = "input", transform = { move = { %s, %s, 0.5 } } } }
	]], w, d, x, y))
end

test("a port placed mid-footprint snaps to the nearest edge, on that edge's tile row", function()
	local port = withPort(3, 2, 1.5, 0.8).roles.ports[1]
	assertEqual("input", port.kind)
	assertEqual("N", port.edge)
	assertNear(1.5, port.x)
	assertNear(0.5, port.y)
end)

test("a snapped port slides with its edge when the footprint grows", function()
	local before = withPort(3, 2, 1.5, 1.8).roles.ports[1]
	assertEqual("S", before.edge)
	assertNear(1.5, before.y)
	local after = withPort(3, 3, 1.5, 1.8).roles.ports[1]
	assertEqual("S", after.edge)
	assertNear(2.5, after.y)
end)

test("a port beyond the footprint's side snaps onto it", function()
	local port = withPort(3, 2, 3.4, 1).roles.ports[1]
	assertEqual("E", port.edge)
	assertNear(2.5, port.x)
	assertNear(1, port.y)
end)

test("storage roles add up", function()
	local bp = compile([[
		return group{ box{}, role{ storage = 8 }, role{ storage = 4 } }
	]])
	assertEqual(12, bp.roles.storage)
end)

-- Config with blueprint tuning `blueprints` (the rest as shipped).
local function tuned(blueprints)
	local config = {}
	for k, v in pairs(Config) do
		config[k] = v
	end
	config.blueprints = blueprints
	return config
end

local COST_TUNING = {
	voxelsPerTile = 16,
	defaultMaterial = "plank",
	voxelsPerItem = { plank = { plank = 64 } },
	traitVoxels = 256,
	roleCosts = {
		abilities = { saw = { stone = 4 } },
		ports = { input = { plank = 1 } },
		storagePerItem = { plank = 0.5 },
	},
}

test("a design costs its voxels plus its roles", function()
	local bp = assert(Compile.design([[
		return group{ box{},
			role{ ability = "saw" },
			role{ port = "input" },
			role{ storage = 8 } }
	]], "design", { prefabs = {} }, tuned(COST_TUNING)))
	-- 4096 plank voxels at 64 a plank, a saw, an input port, 8 storage.
	assertEqual(64 + 1 + 4, bp.cost.plank)
	assertEqual(4, bp.cost.stone)
end)

test("voxel cost rounds up", function()
	local function cost(size)
		return assert(Compile.design("return box{ size = " .. size .. " }", "design", { prefabs = {} }, tuned(COST_TUNING))).cost
	end
	-- 8 x 8 x 1 = 64 voxels, then 9 x 8 x 1 = 72.
	assertEqual(1, cost("{ 0.5, 0.5, 0.0625 }").plank)
	assertEqual(2, cost("{ 0.5625, 0.5, 0.0625 }").plank)
end)

test("an unknown ability is a compile error", function()
	local bp, message = Compile.design('return group{ box{}, role{ ability = "teleport" } }', "design", { prefabs = {} }, Config)
	assertEqual(nil, bp)
	assertTrue(message:find("teleport", 1, true), message)
end)

test("traits and auras come from voxels per material", function()
	local config = tuned(COST_TUNING)
	-- 4096 plank voxels at 256 a point: 16 points of plank.
	local bp = assert(Compile.design("return box{}", "design", { prefabs = {} }, config))
	for name, per in pairs(Config.traits.plank) do
		assertNear(16 * per, bp.traits[name], 1e-9, name)
	end
	for name, per in pairs(Config.auras.plank) do
		assertNear(16 * per, bp.auras[name], 1e-9, name)
	end
end)

test("prefab(name) places a library prefab, moved by its transform", function()
	local bp = compile([[
		return group{ box{ size = { 2, 1, 1 } },
			prefab("saw", { id = "saw1", transform = { move = { 1, 0, 0 } } }) }
	]], {
		saw = 'return group{ box{ size = { 0.5, 0.5, 0.5 } }, role{ ability = "saw", transform = { move = { 0.25, 0.25, 0 } } } }',
	})
	assertEqual(1, #bp.roles.abilities)
	assertNear(1.25, bp.roles.abilities[1].x)
	assertNear(0.25, bp.roles.abilities[1].y)
end)

test("a prefab cycle a -> b -> a is an error that names it", function()
	local bp, message = Compile.design('return prefab("a")', "design", {
		prefabs = { a = 'return group{ box{}, prefab("b") }', b = 'return group{ box{}, prefab("a") }' },
	}, Config)
	assertEqual(nil, bp)
	assertTrue(message:find("a -> b -> a", 1, true), message)
end)

test("a prefab that places itself is an error", function()
	local bp, message = Compile.design('return prefab("a")', "design", { prefabs = { a = 'return prefab("a")' } }, Config)
	assertEqual(nil, bp)
	assertTrue(message:find("cycle", 1, true), message)
end)

test("an unknown prefab is an error that names it", function()
	local bp, message = Compile.design('return prefab("nope")', "design", { prefabs = {} }, Config)
	assertEqual(nil, bp)
	assertTrue(message:find("nope", 1, true), message)
end)

local Builtins = require("tests.support.builtins")

test("every built-in role prefab compiles with one role and a cost", function()
	for _, name in ipairs(require("src.game.designs.builtins").PREFABS) do
		local bp, message = Compile.design(Builtins.prefabs[name], name, Builtins, Config)
		assertTrue(bp, message)
		local r = bp.roles
		local count = #r.abilities + #r.ports + (r.storage > 0 and 1 or 0)
		assertEqual(1, count, name .. " roles")
		assertTrue(next(bp.cost), name .. " has a cost")
	end
end)

test("the storage facility compiles: a depot, storage and both ports on its south edge", function()
	local bp = compile(Builtins.designs.storage_facility, Builtins.prefabs)
	assertEqual(3, bp.width)
	assertEqual(2, bp.depth)
	assertEqual(1, #bp.roles.abilities)
	assertEqual("depot", bp.roles.abilities[1].ability)
	assertEqual(72, bp.roles.storage)
	assertEqual(2, #bp.roles.ports)
	local kinds = {}
	for _, p in ipairs(bp.roles.ports) do
		assertEqual("S", p.edge)
		kinds[p.kind] = math.floor(p.x)
	end
	assertEqual(1, kinds.input, "the input port's column")
	assertEqual(2, kinds.output, "the output port's column")
end)

test("a role needs exactly one of ability, port or storage", function()
	for _, args in ipairs({ "{}", '{ ability = "saw", storage = 2 }', '{ port = "sideways" }', "{ storage = 0 }" }) do
		local bp, message = Compile.design("return group{ box{}, role" .. args .. " }", "design", { prefabs = {} }, Config)
		assertEqual(nil, bp, args)
		assertTrue(message:find("design:1:", 1, true), message)
	end
end)

test("a prefab is found by name only: a path is an unknown name", function()
	local bp, message = Compile.design('return prefab("../designs/storage_facility")', "design", Builtins, Config)
	assertEqual(nil, bp)
	assertTrue(message:find("unknown prefab", 1, true), message)
end)

test("a blueprint with no function role is a problem to place", function()
	local bp = compile([[return group{ box{}, role{ port = "output", transform = { move = { 0.5, 1, 0 } } } }]])
	assertEqual("no function role", Compile.problems(bp, Config)[1])
	local saw = compile([[return group{ box{}, role{ ability = "saw", transform = { move = { 0.5, 0.5, 0 } } } }]])
	assertEqual(0, #Compile.problems(saw, Config))
end)

test("a converting role with no input port is a problem to place", function()
	local bench = [[role{ ability = "sawbench", transform = { move = { 0.5, 0.5, 0 } } }]]
	local bp = compile("return group{ box{ size = { 1, 1, 1 } }, " .. bench .. " }")
	assertEqual("sawbench without input", Compile.problems(bp, Config)[1])
	local fed = compile("return group{ box{ size = { 1, 1, 1 } }, " .. bench
		.. [[, role{ port = "input", transform = { move = { 0.5, 1, 0 } } } }]])
	assertEqual(0, #Compile.problems(fed, Config))
end)

test("voxel cost splits by material: a stone box costs stone, a plank box plank", function()
	local config = tuned({
		voxelsPerTile = 16,
		defaultMaterial = "plank",
		voxelsPerItem = { plank = { plank = 64 }, stone = { stone = 64 } },
		traitVoxels = 256,
		roleCosts = { abilities = {}, ports = {}, storagePerItem = {} },
	})
	local bp = assert(Compile.design([[
		return group{
			box{ material = { name = "stone" } },
			box{ transform = { move = { 1, 0, 0 } } },
		}
	]], "design", { prefabs = {} }, config))
	-- 4096 voxels each at 64 an item.
	assertEqual(64, bp.cost.stone)
	assertEqual(64, bp.cost.plank)
end)

test("changing a variant, scale or rotation never changes cost; changing material does", function()
	local function cost(material)
		return assert(Compile.design("return box{ material = " .. material .. " }", "design", { prefabs = {} }, Config)).cost
	end
	local polished = cost('{ name = "stone" }')
	local brick = cost('{ name = "stone", variant = "brick", scale = 3, rotation = 45 }')
	assertEqual(polished.stone, brick.stone)
	assertEqual(polished.plank, brick.plank)
	local plank = cost('{ name = "plank", variant = "logs" }')
	assertEqual(nil, plank.stone)
	assertEqual(polished.stone, plank.plank)
end)
