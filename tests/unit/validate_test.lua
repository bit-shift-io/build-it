-- Design validation (docs/CONTEXT.md "Function brick", "Port"): each rule
-- fires alone, and a draft that keeps every rule has no problems.
local Validate = require("src.game.builder.validate")
local Draft = require("src.game.builder.draft")
local Config = require("src.game.config")

local CFG = Config.builder

local function held(shape, rotation)
	return { shape = shape, rotation = rotation or 0, material = "plank", paint = 1 }
end

-- A valid 2x2 tile draft (8x8 studs): a saw in the middle and an output
-- port on the south edge.
local function valid()
	local d = Draft.new()
	assert(Draft.resize(d, 2, 2, CFG))
	assert(Draft.place(d, 2, 3, 0, CFG, held("saw")))
	assert(Draft.place(d, 3, 7, 0, CFG, held("output")))
	return d
end

local function remove(d, field, value)
	for _, b in ipairs(d.bricks) do
		if b[field] == value then
			Draft.remove(d, b)
			return
		end
	end
	error("no brick with " .. field .. " " .. tostring(value))
end

-- Asserts `d` breaks exactly `reason`.
local function assertOnly(reason, d)
	local problems = Validate.problems(d, CFG)
	assertEqual(1, #problems, "expected only " .. reason .. ", got " .. table.concat(problems, ", "))
	assertEqual(reason, problems[1])
end

test("a draft with a function brick and an output port on its edge is valid", function()
	assertEqual(0, #Validate.problems(valid(), CFG))
end)

test("a draft without a function brick says so", function()
	local d = valid()
	remove(d, "ability", "saw")
	assertOnly("no function brick", d)
end)

test("a draft without an output port says so", function()
	local d = valid()
	remove(d, "port", "output")
	assertOnly("no output port", d)
end)

test("a port off the footprint edge says so", function()
	local d = valid()
	assert(Draft.place(d, 4, 5, 0, CFG, held("input")))
	assertOnly("port off edge", d)
end)

test("a port above ground level says so, even over the edge", function()
	local d = valid()
	assert(Draft.place(d, 0, 0, 1, CFG, held("input")))
	assertOnly("port off edge", d)
end)

test("a port in a corner is on the edge", function()
	local d = valid()
	assert(Draft.place(d, 0, 0, 0, CFG, held("input", 1)))
	assertEqual(0, #Validate.problems(d, CFG))
end)

test("growing the baseplate leaves a port off the new edge", function()
	local d = valid()
	assert(Draft.resize(d, 2, 3, CFG))
	assertOnly("port off edge", d)
end)

test("a saw bench needs an input port", function()
	local d = valid()
	assert(Draft.place(d, 2, 0, 0, CFG, held("sawbench")))
	assertOnly("saw bench without input", d)
	assert(Draft.place(d, 0, 5, 0, CFG, held("input", 1)))
	assertEqual(0, #Validate.problems(d, CFG))
end)

test("every broken rule is listed, in rule order", function()
	local d = Draft.new()
	assert(Draft.place(d, 1, 1, 0, CFG, held("input")))
	local problems = Validate.problems(d, CFG)
	assertEqual("no function brick", problems[1])
	assertEqual("no output port", problems[2])
	assertEqual("port off edge", problems[3])
	assertEqual(3, #problems)
end)
