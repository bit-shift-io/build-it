-- Settings: player-level choices that outlive any world (docs/CONTEXT.md
-- "Settings"): the view and the two team colours the team palette derives
-- from (src/game/palette.lua). A plain record
--   { view = <name>, primary = { r, g, b }, secondary = { r, g, b } }
-- never part of a world save. Pure data and text, so
-- src/app/settings_store.lua only moves the text to and from disk.
local Palette = require("src.game.palette")

local Settings = {}

-- The team colour fields.
local COLORS = { "primary", "secondary" }

-- The valid view names, from config.views: topdown first, the rest sorted.
function Settings.views(config)
	local names = {}
	for name in pairs(config.views) do
		if name ~= "topdown" then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	table.insert(names, 1, "topdown")
	return names
end

local function copy(c)
	return { c[1], c[2], c[3] }
end

function Settings.default()
	return { view = "topdown", primary = copy(Palette.DEFAULT_PRIMARY), secondary = copy(Palette.DEFAULT_SECONDARY) }
end

-- Whether `c` is a colour: 3 numbers, 0 to 1.
local function isColor(c)
	if type(c) ~= "table" then
		return false
	end
	for i = 1, 3 do
		if type(c[i]) ~= "number" or not (c[i] >= 0 and c[i] <= 1) then
			return false
		end
	end
	return true
end

-- A settings record from `raw` (any value): unknown or missing fields fall
-- back to the defaults.
function Settings.validate(config, raw)
	local settings = Settings.default()
	if type(raw) ~= "table" then
		return settings
	end
	if type(raw.view) == "string" and config.views[raw.view] then
		settings.view = raw.view
	end
	for _, field in ipairs(COLORS) do
		if isColor(raw[field]) then
			settings[field] = copy(raw[field])
		end
	end
	return settings
end

-- The team palette of `settings`' two colours.
function Settings.palette(settings)
	return Palette.derive(settings.primary, settings.secondary)
end

-- `x` in the fewest digits that read back as exactly `x`.
local function number(x)
	for digits = 14, 17 do
		local s = string.format("%." .. digits .. "g", x)
		if tonumber(s) == x then
			return s
		end
	end
	return string.format("%.17g", x)
end

-- One "key=value" line per field: the view's name, a colour's three
-- channels spaced.
function Settings.encode(settings)
	local lines = { "view=" .. settings.view }
	for _, field in ipairs(COLORS) do
		local c = settings[field]
		lines[#lines + 1] = field .. "=" .. number(c[1]) .. " " .. number(c[2]) .. " " .. number(c[3])
	end
	return table.concat(lines, "\n") .. "\n"
end

-- The settings in `text`; garbage or nil gives the defaults, field by field.
function Settings.decode(config, text)
	local raw = {}
	if type(text) == "string" then
		for line in text:gmatch("[^\n]+") do
			local key, value = line:match("^(%w+)=(.-)%s*$")
			if key == "view" then
				raw.view = value:match("^[%w_]+$")
			elseif key == "primary" or key == "secondary" then
				local c = {}
				for word in value:gmatch("%S+") do
					c[#c + 1] = tonumber(word)
				end
				raw[key] = #c == 3 and c or nil
			end
		end
	end
	return Settings.validate(config, raw)
end

return Settings
