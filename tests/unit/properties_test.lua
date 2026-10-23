-- A selected primitive's properties (src/game/builder/properties.lua): the
-- dimensions and segments the builder's properties strip edits, each edit
-- a scene edit the undo history can take.
local Sandbox = require("src.game.script.sandbox")
local Scene = require("src.game.builder.scene")
local Properties = require("src.game.builder.properties")

local function sceneOf(text)
	return Scene.new(assert(Sandbox.run(text, "design")).root)
end

local function keys(props)
	local out = {}
	for i, p in ipairs(props) do
		out[i] = p.key .. "=" .. tostring(p.value)
	end
	return table.concat(out, " ")
end

test("each primitive lists its dimensions and segments; groups and prefabs have none", function()
	local scene = sceneOf([[return group{ id = "root",
		box{ id = "b", size = { 2, 1, 3 } },
		sphere{ id = "s", radius = 0.5, segments = 16 },
		cylinder{ id = "c", radius = 0.25, height = 2, segments = 12 },
		cone{ id = "k" },
		wedge{ id = "w", size = { 1, 2, 0.5 } },
		prefab("saw", { id = "saw" }),
	}]])
	assertEqual("width=2 depth=1 height=3", keys(Properties.of(Scene.find(scene, "b"))))
	assertEqual("radius=0.5 segments=16", keys(Properties.of(Scene.find(scene, "s"))))
	assertEqual("radius=0.25 height=2 segments=12", keys(Properties.of(Scene.find(scene, "c"))))
	assertEqual("radius=0.5 height=1 segments=24", keys(Properties.of(Scene.find(scene, "k"))))
	assertEqual("width=1 depth=2 height=0.5", keys(Properties.of(Scene.find(scene, "w"))))
	assertEqual(0, #Properties.of(Scene.find(scene, "saw")))
	assertEqual(0, #Properties.of(scene.root))
end)

test("setting a property changes that node; a bad value is refused with why and changes nothing", function()
	local scene = sceneOf('return group{ id = "root", box{ id = "b" }, cylinder{ id = "c" } }')
	assertTrue(Properties.set(scene, "b", "depth", 2.5))
	assertEqual(2.5, Scene.find(scene, "b").size[2])
	assertEqual(1, Scene.find(scene, "b").size[1])
	assertTrue(Properties.set(scene, "c", "segments", 8))
	assertEqual(8, Scene.find(scene, "c").segments)
	local ok, reason = Properties.set(scene, "c", "radius", 0)
	assertFalse(ok)
	assertTrue(reason:find("above 0", 1, true), reason)
	ok, reason = Properties.set(scene, "c", "segments", 2.5)
	assertFalse(ok)
	assertTrue(reason:find("whole", 1, true), reason)
	assertFalse(Properties.set(scene, "c", "segments", 1000))
	assertFalse(Properties.set(scene, "c", "radius", nil))
	assertEqual(0.5, Scene.find(scene, "c").radius)
	assertEqual(8, Scene.find(scene, "c").segments)
end)
