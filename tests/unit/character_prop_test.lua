local Character = require("src.game.props.character")
local Model = require("src.game.blocks.model")

local function directionIndex(name)
	for i, d in ipairs(Character.DIRECTIONS) do
		if d.name == name then
			return i
		end
	end
	error("no direction " .. name)
end

local function model(name, frame)
	return Character.model(directionIndex(name), frame or Character.IDLE)
end

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

test("every direction and frame is a 16-voxel model standing on its 1x1 footprint with every part", function()
	assertEqual(8, #Character.DIRECTIONS)
	assertEqual(5, Character.FRAMES)
	for dir = 1, #Character.DIRECTIONS do
		for _, frame in ipairs(frames()) do
			local m = Character.model(dir, frame)
			local b = Model.bounds(m)
			local label = Character.DIRECTIONS[dir].name .. " frame " .. frame
			assertEqual(16, m.cellsPerTile)
			assertEqual(1, m.width)
			assertEqual(1, m.depth)
			assertTrue(b.minX >= 0 and b.minY >= 0 and b.maxX <= 16 and b.maxY <= 16, label .. " inside the footprint")
			assertEqual(0, b.minZ, label .. " standing on the ground")
			for _, name in ipairs(PARTS) do
				assertTrue(#part(m, name) > 0, label .. " has a " .. name)
			end
		end
	end
end)

-- The cells the camera sees a south face of on the head: the southmost cell
-- of each (x, z) column of head, hair and eyes.
local function headFront(m)
	local front = {}
	for _, c in ipairs(m.cells) do
		if c.part == "head" or c.part == "hair" or c.part == "eyes" then
			local k = c.x .. "," .. c.z
			if not front[k] or front[k].y < c.y then
				front[k] = c
			end
		end
	end
	return front
end

local function frontParts(m)
	local seen = {}
	for _, c in pairs(headFront(m)) do
		seen[c.part] = (seen[c.part] or 0) + 1
	end
	return seen
end

test("the eyes show toward the camera facing S, SE and SW, and never facing N, NE or NW", function()
	for _, name in ipairs({ "S", "SE", "SW" }) do
		assertEqual(2, frontParts(model(name)).eyes, name .. " shows both eyes")
	end
	for _, name in ipairs({ "N", "NE", "NW" }) do
		assertEqual(nil, frontParts(model(name)).eyes, name .. " shows no eyes")
	end
end)

test("side views point the nose the way they face", function()
	local _, headE = part(model("E"), "head")
	local _, noseE = part(model("E"), "nose")
	assertEqual(headE.maxX, noseE.minX, "facing E the nose sticks out east")
	local _, headW = part(model("W"), "head")
	local _, noseW = part(model("W"), "nose")
	assertEqual(headW.minX, noseW.maxX, "facing W the nose sticks out west")
end)

test("a diagonal turns the head: the face slides toward it", function()
	local _, eyesS = part(model("S"), "eyes")
	local _, eyesSE = part(model("SE"), "eyes")
	local _, eyesSW = part(model("SW"), "eyes")
	assertEqual(eyesS.minX + 1, eyesSE.minX)
	assertEqual(eyesS.minX - 1, eyesSW.minX)
	-- Facing away, the cheek on the turned side shows past the back hair.
	local function frontSkinXs(name)
		local xs = {}
		for _, c in pairs(headFront(model(name))) do
			if c.part == "head" and c.z >= 11 and c.z < 15 then
				xs[c.x] = true
			end
		end
		return xs
	end
	assertTrue(next(frontSkinXs("N")) == nil, "N shows only hair from behind")
	assertTrue(frontSkinXs("NE")[10] and not frontSkinXs("NE")[5], "NE shows its east cheek")
	assertTrue(frontSkinXs("NW")[5] and not frontSkinXs("NW")[10], "NW shows its west cheek")
end)

-- A part's offset between two frames, as bounds deltas.
local function moved(dirName, name, frame)
	local _, idle = part(model(dirName), name)
	local _, posed = part(model(dirName, frame), name)
	return posed.minX - idle.minX, posed.minY - idle.minY, posed.minZ - idle.minZ
end

test("walking strides the legs and swings the arms along the facing", function()
	local stride = Character.WALK[1]
	-- Facing S the left leg steps forward (south), the right back; the arms
	-- swing the other way round.
	local x, y = moved("S", "legL", stride)
	assertEqual(0, x)
	assertTrue(y > 0, "S: left leg forward")
	x, y = moved("S", "legR", stride)
	assertTrue(y < 0, "S: right leg back")
	x, y = moved("S", "armR", stride)
	assertTrue(y > 0, "S: right arm forward")
	-- Facing E the same stride runs along x.
	x, y = moved("E", "legL", stride)
	assertTrue(x > 0 and y == 0, "E: left leg forward, east")
	-- Diagonals stride along both axes.
	x, y = moved("NW", "legL", stride)
	assertTrue(x < 0 and y < 0, "NW: left leg forward, north-west")
end)

test("the walk cycle mirrors: the second stride swaps the legs, and every walk frame differs from idle", function()
	local first, second = Character.WALK[1], Character.WALK[3]
	local _, y1 = moved("S", "legL", first)
	local _, y2 = moved("S", "legR", second)
	assertEqual(y1, y2)
	local function cellsKey(m)
		local parts = {}
		for _, c in ipairs(m.cells) do
			parts[#parts + 1] = c.x .. "," .. c.y .. "," .. c.z .. "," .. c.part
		end
		table.sort(parts)
		return table.concat(parts, ";")
	end
	local seen = { [cellsKey(model("S"))] = "idle" }
	for _, f in ipairs(Character.WALK) do
		local key = cellsKey(model("S", f))
		assertEqual(nil, seen[key], "walk frame " .. f .. " is a new pose")
		seen[key] = f
	end
end)

test("the registry's character kind bakes 8 directions as variants and 5 frames as stages", function()
	local Registry = require("src.game.props.registry")
	local Config = require("src.game.config")
	local def = Registry.CHARACTER
	assertEqual("character", def.kind)
	assertEqual(Character.VERSION, def.version)
	assertEqual(#Character.DIRECTIONS, def.variants)
	assertEqual(Character.FRAMES, def.stages)
	assertTrue(Registry.KINDS.character == nil, "the character is not a resource node kind")
	local m = Registry.model(def, directionIndex("SW"), Character.WALK[2], Config)
	assertEqual(#Character.model(directionIndex("SW"), Character.WALK[2]).cells, #m.cells)
	local _, eyes = part(m, "eyes")
	local _, eyesS = part(model("S"), "eyes")
	assertEqual(eyesS.minX - 1, eyes.minX, "variant picks the direction")
end)

test("the villager kind bakes the same figure in config.villagers.shirt, keyed by that colour", function()
	local Registry = require("src.game.props.registry")
	local Config = require("src.game.config")
	local def = Registry.villager(Config)
	assertEqual("villager", def.kind)
	assertEqual(#Character.DIRECTIONS, def.variants)
	assertEqual(Character.FRAMES, def.stages)
	local m = Registry.model(def, directionIndex("E"), Character.WALK[1], Config)
	local plain = model("E", Character.WALK[1])
	assertEqual(#plain.cells, #m.cells)
	local body = part(m, "body")
	assertEqual(Config.villagers.shirt, body[1].color)
	local plainBody = part(plain, "body")
	assertTrue(plainBody[1].color ~= Config.villagers.shirt, "the player's shirt is unchanged")

	local other = { villagers = { shirt = { 0.1, 0.2, 0.3 } }, props = Config.props }
	assertTrue(Registry.villager(other).version ~= def.version, "another shirt colour is another bake key")
	assertEqual(def.version, Registry.villager(Config).version)
end)
