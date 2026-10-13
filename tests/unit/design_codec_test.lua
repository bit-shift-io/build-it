local Codec = require("src.game.designs.codec")

local function brick(x, fields)
	local b = { x = x, y = 1, z = 0, width = 2, depth = 2, shape = "2x2", rotation = 1, material = "stone", paint = 7 }
	for k, v in pairs(fields or {}) do
		b[k] = v
	end
	return b
end

-- Every field of `a` and `b`, compared one level deep, plus their brick lists.
local function assertSameVersion(a, b, label)
	for k, v in pairs(a) do
		if k ~= "bricks" then
			assertEqual(v, b[k], label .. " field " .. k)
		end
	end
	assertEqual(#a.bricks, #b.bricks, label .. " brick count")
	for i, ab in ipairs(a.bricks) do
		local bb = b.bricks[i]
		for k, v in pairs(ab) do
			assertEqual(v, bb[k], string.format("%s brick %d field %s", label, i, k))
		end
		for k in pairs(bb) do
			assertTrue(ab[k] ~= nil, string.format("%s brick %d grew field %s", label, i, k))
		end
	end
end

test("a design with two versions round-trips through the codec", function()
	local design = {
		id = "d3",
		name = "Saw mill",
		versions = {
			{ width = 1, depth = 1, bricks = { brick(0) } },
			{ width = 2, depth = 3, bricks = { brick(0), brick(4, { shape = "slope", rotation = 3, material = "plank", paint = 12 }) } },
		},
	}
	local decoded = assert(Codec.decode(Codec.encode(design)))
	assertEqual("d3", decoded.id)
	assertEqual("Saw mill", decoded.name)
	assertEqual(2, #decoded.versions)
	assertSameVersion(design.versions[1], decoded.versions[1], "v1")
	assertSameVersion(design.versions[2], decoded.versions[2], "v2")
end)

test("fields the codec has never heard of round-trip with their types", function()
	local design = {
		id = "d1",
		name = "Ünïcode % = \"quoted\"\nnew line",
		versions = {
			{
				width = 1,
				depth = 1,
				bricks = { brick(0, { kind = "saw", port = "in", facing = 2, powered = true, broken = false, ratio = 0.125 }) },
			},
		},
	}
	local decoded = assert(Codec.decode(Codec.encode(design)))
	assertEqual(design.name, decoded.name)
	assertSameVersion(design.versions[1], decoded.versions[1], "v1")
	assertEqual(true, decoded.versions[1].bricks[1].powered)
	assertEqual(false, decoded.versions[1].bricks[1].broken)
end)

test("corrupt text is reported, not thrown", function()
	local good = Codec.encode({ id = "d1", name = "A", versions = { { width = 1, depth = 1, bricks = { brick(0) } } } })
	local cases = {
		["empty"] = "",
		["wrong header"] = "hello\n",
		["truncated before any version"] = good:match("^[^\n]+\n[^\n]+\n"),
		["bad value"] = good:gsub("paint=n:7", "paint=q:7"),
		["bad escape"] = good:gsub("name=s:A", "name=s:A%%4"),
		["brick missing x"] = good:gsub(" x=n:0", ""),
		["garbage line"] = good .. "\0\1\2 ==\n",
	}
	for label, text in pairs(cases) do
		local ok, design, reason = pcall(Codec.decode, text)
		assertTrue(ok, label .. ": decode threw " .. tostring(design))
		assertEqual(nil, design, label .. ": expected no design")
		assertEqual("string", type(reason), label .. ": expected a reason")
	end
end)
