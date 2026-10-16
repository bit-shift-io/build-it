-- Turns a design (src/game/designs/library.lua) into the text of its file
-- in the design library, and back. Pure -- no `love.*`.
--
-- The format is line based, one record per line:
--
--   build-it-design 1
--   design id=s:d1 name=s:Saw%20mill
--   version depth=n:1 width=n:1
--   brick depth=n:2 material=s:plank paint=n:1 ... x=n:0 y=n:0 z=n:0
--   version ...
--
-- A record is a tag and its fields as key=value. Brick lines belong to the
-- version line above them. Values carry their type: n: a number, b: a
-- boolean (true/false), s: a string with every byte outside [%w-_.~]
-- written as %XX. Fields are written generically, whatever a design,
-- version or brick carries, so new brick fields save without codec changes.
-- Keys are identifiers; values are numbers, strings or booleans.
local Codec = {}

local HEADER = "build-it-design 1"

local function escape(s)
	return (s:gsub("[^%w%-_%.~]", function(c)
		return string.format("%%%02X", c:byte())
	end))
end

local function unescape(s)
	return (s:gsub("%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end))
end

local function encodeValue(key, v)
	local t = type(v)
	if t == "number" then
		return "n:" .. string.format("%.17g", v)
	elseif t == "boolean" then
		return "b:" .. tostring(v)
	elseif t == "string" then
		return "s:" .. escape(v)
	end
	error("cannot save field " .. key .. " of type " .. t)
end

-- One record: `tag` and every field of `t` except `skip`, sorted by key.
-- Shared with the world save (src/game/save/codec.lua).
local function record(tag, t, skip)
	local keys = {}
	for k in pairs(t) do
		if k ~= skip then
			assert(type(k) == "string" and k:match("^[%a_][%w_]*$"), "cannot save field " .. tostring(k))
			keys[#keys + 1] = k
		end
	end
	table.sort(keys)
	local parts = { tag }
	for _, k in ipairs(keys) do
		parts[#parts + 1] = k .. "=" .. encodeValue(k, t[k])
	end
	return table.concat(parts, " ")
end

-- The file text of `design` = { id, name, versions = { <version>, ... } },
-- version = { width, depth, bricks = { <brick>, ... } }.
function Codec.encode(design)
	local lines = { HEADER, record("design", design, "versions") }
	for _, version in ipairs(design.versions) do
		lines[#lines + 1] = record("version", version, "bricks")
		for _, brick in ipairs(version.bricks) do
			lines[#lines + 1] = record("brick", brick)
		end
	end
	return table.concat(lines, "\n") .. "\n"
end

local function decodeValue(text)
	local kind, raw = text:match("^(%a):(.*)$")
	if kind == "n" then
		return tonumber(raw)
	elseif kind == "b" and (raw == "true" or raw == "false") then
		return raw == "true"
	elseif kind == "s" and not raw:find("%%[^%x]") and not raw:find("%%%x?$") then
		return unescape(raw)
	end
	return nil
end

-- The tag and fields of line number `n`, or nil and why. Shared with the
-- world save.
local function parseRecord(line, n)
	local tag, rest = line:match("^(%a+)(.*)$")
	if not tag then
		return nil, "line " .. n .. " has no record tag"
	end
	local fields = {}
	for token in rest:gmatch("%S+") do
		local key, raw = token:match("^([%a_][%w_]*)=(.+)$")
		local value = raw and decodeValue(raw)
		if value == nil then
			return nil, "line " .. n .. " has a bad field: " .. token
		end
		fields[key] = value
	end
	return tag, fields
end

local REQUIRED = {
	design = { id = "string", name = "string" },
	version = { width = "number", depth = "number" },
	brick = { x = "number", y = "number", z = "number", width = "number", depth = "number" },
}

local function missing(tag, fields)
	for key, kind in pairs(REQUIRED[tag]) do
		if type(fields[key]) ~= kind then
			return key
		end
	end
	return nil
end

-- The design in file text `text`, or nil and why it could not be read.
function Codec.decode(text)
	if type(text) ~= "string" then
		return nil, "no text"
	end
	local design, version = nil, nil
	local n = 0
	for line in text:gmatch("[^\n]+") do
		n = n + 1
		if n == 1 then
			if line ~= HEADER then
				return nil, "not a design file"
			end
		else
			local tag, fields = parseRecord(line, n)
			if not tag then
				return nil, fields
			end
			if not REQUIRED[tag] then
				return nil, "line " .. n .. " has an unknown record " .. tag
			end
			local key = missing(tag, fields)
			if key then
				return nil, "line " .. n .. " lacks " .. key
			end
			if tag == "design" then
				if design then
					return nil, "line " .. n .. " is a second design record"
				end
				design = fields
				design.versions = {}
			elseif not design then
				return nil, "line " .. n .. " comes before the design record"
			elseif tag == "version" then
				version = fields
				version.bricks = {}
				table.insert(design.versions, version)
			elseif not version then
				return nil, "line " .. n .. " is a brick outside any version"
			else
				table.insert(version.bricks, fields)
			end
		end
	end
	if not design then
		return nil, "no design record"
	end
	if #design.versions == 0 then
		return nil, "no versions"
	end
	return design
end

Codec.record = record
Codec.parseRecord = parseRecord

return Codec
