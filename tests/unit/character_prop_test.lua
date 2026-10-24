-- The character prop (src/game/props/character.lua): one figure per frame,
-- authored facing N. The baker turns it to each of the 8 facings
-- (Registry.turn), so facing never shapes the voxels.
local Character = require("src.game.props.character")
local Model = require("src.game.blocks.model")

local function frames()
	local all = { Character.IDLE }
	for _, f in ipairs(Character.WALK) do
		all[#all + 1] = f
	end
	return all
end

-- The cells of one part, and their bounds (cells, max exclusive).
local function part(m, name)
	local cells = {}
	for _, c in ipairs(m.cells) do
		if c.part == name then
			cells[#cells + 1] = c
		end
	end
	return cells, Model.bounds({ cells = cells })
end

local PARTS = { "legL", "legR", "body", "armL", "armR", "head", "hair", "eyes", "nose" }

test("every frame is a 32-voxel model standing on its 1x1 footprint with every part", function()
	assertEqual(8, #Character.DIRECTIONS)
	assertEqual(5, Character.FRAMES)
	for _, frame in ipairs(frames()) do
		local m = Character.model(frame)
		local b = Model.bounds(m)
		local label = "frame " .. frame
		assertEqual(32, m.cellsPerTile)
		assertEqual(1, m.width)
		assertEqual(1, m.depth)
		assertTrue(b.minX >= 0 and b.minY >= 0 and b.maxX <= 32 and b.maxY <= 32, label .. " inside the footprint")
		assertEqual(0, b.minZ, label .. " standing on the ground")
		for _, name in ipairs(PARTS) do
			assertTrue(#part(m, name) > 0, label .. " has a " .. name)
		end
	end
end)

test("the figure is authored facing N: face and nose on the head's north side, hair on its south", function()
	local m = Character.model(Character.IDLE)
	local _, head = part(m, "head")
	local _, eyes = part(m, "eyes")
	local _, nose = part(m, "nose")
	assertEqual(head.minY, nose.maxY, "the nose sticks out north")
	assertEqual(head.minY, eyes.minY, "the eyes are on the north face")
	-- Seen from the south, the back of the head is all hair.
	local southmost = {}
	for _, c in ipairs(m.cells) do
		if (c.part == "head" or c.part == "hair" or c.part == "eyes") and c.z >= 11 then
			local k = c.x .. "," .. c.z
			if not southmost[k] or southmost[k].y < c.y then
				southmost[k] = c
			end
		end
	end
	for _, c in pairs(southmost) do
		assertEqual("hair", c.part)
	end
end)

-- A part's offset between idle and `frame`, as bounds deltas.
local function moved(name, frame)
	local _, idle = part(Character.model(Character.IDLE), name)
	local _, posed = part(Character.model(frame), name)
	return posed.minX - idle.minX, posed.minY - idle.minY, posed.minZ - idle.minZ
end

test("walking strides the legs and swings the arms forward and back, north and south", function()
	local stride = Character.WALK[1]
	local x, y = moved("legL", stride)
	assertTrue(x == 0 and y < 0, "left leg forward")
	x, y = moved("legR", stride)
	assertTrue(x == 0 and y > 0, "right leg back")
	x, y = moved("armR", stride)
	assertTrue(x == 0 and y < 0, "right arm forward")
end)

test("the walk cycle mirrors: the second stride swaps the legs, and every walk frame differs from idle", function()
	local _, y1 = moved("legL", Character.WALK[1])
	local _, y2 = moved("legR", Character.WALK[3])
	assertEqual(y1, y2)
	local function cellsKey(m)
		local parts = {}
		for _, c in ipairs(m.cells) do
			parts[#parts + 1] = c.x .. "," .. c.y .. "," .. c.z .. "," .. c.part
		end
		table.sort(parts)
		return table.concat(parts, ";")
	end
	local seen = { [cellsKey(Character.model(Character.IDLE))] = "idle" }
	for _, f in ipairs(Character.WALK) do
		local key = cellsKey(Character.model(f))
		assertEqual(nil, seen[key], "walk frame " .. f .. " is a new pose")
		seen[key] = f
	end
end)

test("the registry turns character and villager variant k by (k - 1) x 45 degrees, and trees not at all", function()
	local Registry = require("src.game.props.registry")
	local Config = require("src.game.config")
	for _, def in ipairs({ Registry.CHARACTER, Registry.villager(Config) }) do
		for k = 1, 8 do
			assertEqual((k - 1) * 45, Registry.turn(def, k), def.kind .. " variant " .. k)
		end
	end
	assertEqual(0, Registry.turn(Registry.KINDS.tree, 3))
end)

test("the registry's character kind bakes 8 facings of one model per frame", function()
	local Registry = require("src.game.props.registry")
	local Config = require("src.game.config")
	local def = Registry.CHARACTER
	assertEqual("character", def.kind)
	assertEqual(Character.VERSION, def.version)
	assertEqual(#Character.DIRECTIONS, def.variants)
	assertEqual(Character.FRAMES, def.stages)
	assertTrue(Registry.KINDS.character == nil, "the character is not a resource node kind")
	local frame = Character.WALK[2]
	local expected = #Character.model(frame).cells
	for k = 1, 8 do
		assertEqual(expected, #Registry.model(def, k, frame, Config).cells, "variant " .. k .. " is the same model")
	end
end)

test("the villager kind bakes the same figure in config.villagers.shirt, keyed by that colour", function()
	local Registry = require("src.game.props.registry")
	local Config = require("src.game.config")
	local def = Registry.villager(Config)
	assertEqual("villager", def.kind)
	assertEqual(#Character.DIRECTIONS, def.variants)
	assertEqual(Character.FRAMES, def.stages)
	local m = Registry.model(def, 3, Character.WALK[1], Config)
	local plain = Character.model(Character.WALK[1])
	assertEqual(#plain.cells, #m.cells)
	local body = part(m, "body")
	assertEqual(Config.villagers.shirt, body[1].color)
	local plainBody = part(plain, "body")
	assertTrue(plainBody[1].color ~= Config.villagers.shirt, "the player's shirt is unchanged")

	local other = { villagers = { shirt = { 0.1, 0.2, 0.3 } }, props = Config.props }
	assertTrue(Registry.villager(other).version ~= def.version, "another shirt colour is another bake key")
	assertEqual(def.version, Registry.villager(Config).version)
end)
