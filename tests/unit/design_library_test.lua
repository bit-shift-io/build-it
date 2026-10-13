local Library = require("src.game.designs.library")
local Codec = require("src.game.designs.codec")
local Draft = require("src.game.builder.draft")
local Config = require("src.game.config")

local CFG = Config.builder

local function draftWith(n)
	local d = Draft.new()
	d.width = 2
	for i = 1, n do
		assert(Draft.place(d, (i - 1) * 2, 0, 0, CFG, { shape = "2x2", rotation = 0, material = "plank", paint = i }))
	end
	return d
end

test("saving a draft makes a new design with one version", function()
	local lib = Library.new()
	local design, n = Library.save(lib, nil, "Hut", draftWith(1))
	assertEqual(1, n)
	assertEqual("Hut", design.name)
	assertEqual(1, #design.versions)
	assertEqual(2, design.versions[1].width)
	assertEqual(1, #design.versions[1].bricks)
	assertEqual(design, Library.design(lib, design.id))
end)

test("saving again appends a version and never touches the older one", function()
	local lib = Library.new()
	local draft = draftWith(1)
	local design = Library.save(lib, nil, "Hut", draft)
	local v1 = design.versions[1]
	local before = Codec.encode(design)

	-- Edit the same draft in place: paint, place, resize.
	Draft.paint(draft, draft.bricks[1], 9)
	assert(Draft.place(draft, 2, 0, 0, CFG, { shape = "1x1", rotation = 0, material = "stone", paint = 3 }))
	draft.depth = 2
	assertEqual(before, Codec.encode(design), "expected editing the draft to leave version 1 alone")

	local again, n = Library.save(lib, design.id, "Big hut", draft)
	assertEqual(design, again)
	assertEqual(2, n)
	assertEqual(v1, design.versions[1])
	assertEqual(1, #v1.bricks)
	assertEqual(1, v1.bricks[1].paint)
	assertEqual(1, v1.depth)
	assertEqual(2, #design.versions[2].bricks)
	assertEqual("Big hut", design.name, "the name is the design's label")
	assertEqual(1, #lib.designs)
end)

test("opening a version hands out a draft copy, so editing it leaves the version alone", function()
	local lib = Library.new()
	local design = Library.save(lib, nil, "Hut", draftWith(2))
	local draft = Library.toDraft(design.versions[1])
	assertEqual(2, #draft.bricks)
	assertEqual(2, draft.width)
	Draft.remove(draft, draft.bricks[1])
	Draft.paint(draft, draft.bricks[1], 12)
	assertEqual(2, #design.versions[1].bricks)
	assertEqual(2, design.versions[1].bricks[2].paint)
end)

test("new designs get fresh ids", function()
	local lib = Library.new()
	local a = Library.save(lib, nil, "A", draftWith(1))
	local b = Library.save(lib, nil, "A", draftWith(1))
	assertTrue(a.id ~= b.id)
	assertEqual(2, #lib.designs)
end)

test("only a draft with at least one brick can be saved", function()
	local ok, reason = Library.canSave(Draft.new())
	assertFalse(ok)
	assertEqual("empty", reason)
	assertTrue(Library.canSave(draftWith(1)))
end)

test("a library rebuilds from its files, and a corrupt file is reported, not fatal", function()
	local lib = Library.new()
	local hut = Library.save(lib, nil, "Hut", draftWith(1))
	Library.save(lib, hut.id, "Hut", draftWith(2))
	local tower = Library.save(lib, nil, "Tower", draftWith(1))

	local loaded, problems = Library.fromFiles({
		{ name = "d1.design", text = Codec.encode(hut) },
		{ name = "broken.design", text = "build-it-design 1\nversion width=n:1\n" },
		{ name = "d2.design", text = Codec.encode(tower) },
	})
	assertEqual(2, #loaded.designs)
	assertEqual("Hut", loaded.designs[1].name)
	assertEqual(2, #Library.design(loaded, hut.id).versions)
	assertEqual("Tower", Library.design(loaded, tower.id).name)
	assertEqual(1, #problems)
	assertEqual("broken.design", problems[1].name)
	assertEqual("string", type(problems[1].reason))

	-- The next new design never reuses a loaded id.
	local fresh = Library.save(loaded, nil, "New", draftWith(1))
	assertEqual("d3", fresh.id)
end)

test("two files claiming one design id: the second is reported", function()
	local lib = Library.new()
	local hut = Library.save(lib, nil, "Hut", draftWith(1))
	local text = Codec.encode(hut)
	local loaded, problems = Library.fromFiles({ { name = "d1.design", text = text }, { name = "copy.design", text = text } })
	assertEqual(1, #loaded.designs)
	assertEqual(1, #problems)
	assertEqual("copy.design", problems[1].name)
end)
