-- The line record format of the world save (src/game/save/codec.lua). Pure
-- -- no `love.*`.
--
--   tag key=n:1 key=s:text key=b:true ...
--
-- A record is a tag and its fields as key=value. Values carry their type:
-- n: a number (exact, %.17g), b: a boolean (true/false), s: a string with
-- every byte outside [%w-_.~] written as %XX. Fields are written
-- generically, whatever a table carries, sorted by key. Keys are
-- identifiers; values are numbers, strings or booleans.
local Records = {}

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
function Records.record(tag, t, skip)
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

-- The tag and fields of `line`, line number `n`, or nil and why.
function Records.parse(line, n)
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

return Records
