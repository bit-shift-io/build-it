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

test("retired versions round-trip as placeholders with the same numbers", function()
	local design = {
		id = "d2",
		name = "Hut",
		versions = {
			{ width = 1, depth = 1, bricks = { brick(0) } },
			{ width = 2, depth = 2, bricks = { brick(0), brick(2) } },
			{ width = 1, depth = 2, bricks = { brick(0) } },
		},
		retired = { [2] = true },
	}
	local text = Codec.encode(design)
	assertFalse(text:find("x=n:2") ~= nil, "a retired version's bricks are not written")
	local decoded = assert(Codec.decode(text))
	assertEqual(3, #decoded.versions)
	assertTrue(decoded.retired[2])
	assertEqual(nil, decoded.retired[1])
	assertEqual(nil, decoded.retired[3])
	assertEqual(0, #decoded.versions[2].bricks)
	assertSameVersion(design.versions[1], decoded.versions[1], "v1")
	assertSameVersion(design.versions[3], decoded.versions[3], "v3")
end)

test("a design whose every version is retired still encodes and decodes", function()
	local design = {
		id = "d4",
		name = "Gone",
		versions = { { width = 1, depth = 1, bricks = { brick(0) } } },
		retired = { [1] = true },
	}
	local decoded, reason = Codec.decode(Codec.encode(design))
	assert(decoded, reason)
	assertEqual("d4", decoded.id)
	assertEqual(1, #decoded.versions)
	assertTrue(decoded.retired[1])
end)

test("a retired record out of order is reported", function()
	local text = "build-it-design 1\ndesign id=s:d1 name=s:A\nretired n=n:2\n"
	local design, reason = Codec.decode(text)
	assertEqual(nil, design)
	assertEqual("string", type(reason))
end)

test("a file without retired records decodes with nothing retired", function()
	local text = "build-it-design 1\ndesign id=s:d1 name=s:A\nversion depth=n:1 width=n:1\n"
		.. "brick depth=n:2 width=n:2 x=n:0 y=n:0 z=n:0\n"
	local design = assert(Codec.decode(text))
	assertEqual(1, #design.versions)
	assertEqual(1, #design.versions[1].bricks)
	assertEqual(nil, design.retired)
end)
