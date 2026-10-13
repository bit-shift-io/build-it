-- The design library (docs/CONTEXT.md "Design library"): every design the
-- player has saved, with all its versions. Pure -- no `love.*`; reading and
-- writing the files is src/app/design_store.lua's job.
--
--   library = { designs = { <design>, ... } } -- in id order
--   design  = { id, name, versions = { <version>, ... } }
--   version = { width, depth, bricks = { <brick>, ... } } -- a draft's shape
--
-- A version is immutable once saved: the library copies drafts in and out,
-- so editing a draft never reaches a saved version. The name is a label
-- only; ids ("d1", "d2", ...) name the files.
local Codec = require("src.game.designs.codec")

local Library = {}

function Library.new()
	return { designs = {} }
end

local function copy(t)
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	return out
end

-- A deep copy of a draft-shaped table: its fields and a copy of each brick.
local function copyDraft(d)
	local out = copy(d)
	out.bricks = {}
	for i, b in ipairs(d.bricks) do
		out.bricks[i] = copy(b)
	end
	return out
end

function Library.design(lib, id)
	for _, design in ipairs(lib.designs) do
		if design.id == id then
			return design
		end
	end
	return nil
end

local function idNumber(id)
	return tonumber(id:match("^d(%d+)$")) or 0
end

local function newId(lib)
	local max = 0
	for _, design in ipairs(lib.designs) do
		max = math.max(max, idNumber(design.id))
	end
	return "d" .. (max + 1)
end

local function insert(lib, design)
	table.insert(lib.designs, design)
	table.sort(lib.designs, function(a, b)
		return idNumber(a.id) < idNumber(b.id)
	end)
end

-- Saves `draft` as the next version of design `id`, or as a new design when
-- id is nil, labelled `name`. Returns the design and the new version's
-- number.
function Library.save(lib, id, name, draft)
	local design = id and Library.design(lib, id)
	if not design then
		design = { id = id or newId(lib), versions = {} }
		insert(lib, design)
	end
	design.name = name
	table.insert(design.versions, copyDraft(draft))
	return design, #design.versions
end

-- Whether `draft` is a valid design to save: true, or false and why.
-- The one rule set the builder's save path checks; for now a design needs
-- at least one brick ("empty"). Cost never matters: designs save even when
-- unaffordable.
function Library.canSave(draft)
	if #draft.bricks == 0 then
		return false, "empty"
	end
	return true
end

-- A library from its files, each { name, text } (src/game/designs/codec.lua
-- text). Returns the library and its problems, one { name, reason } per
-- file that could not be read; those files are left out.
function Library.fromFiles(files)
	local lib, problems = Library.new(), {}
	for _, file in ipairs(files) do
		local design, reason = Codec.decode(file.text)
		if design and Library.design(lib, design.id) then
			design, reason = nil, "another file already holds design " .. design.id
		end
		if design then
			insert(lib, design)
		else
			table.insert(problems, { name = file.name, reason = reason })
		end
	end
	return lib, problems
end

-- A fresh draft (src/game/builder/draft.lua) of `version`, to edit freely.
function Library.toDraft(version)
	return copyDraft(version)
end

return Library
