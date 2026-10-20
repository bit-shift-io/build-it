-- Settings: player-level choices that outlive any world (docs/CONTEXT.md
-- "Settings"). Today just the view. A plain record { view = <name> }, never
-- part of a world save. Pure data and text, so src/app/settings_store.lua
-- only moves the text to and from disk.
local Settings = {}

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

function Settings.default()
	return { view = "topdown" }
end

-- A settings record from `raw` (any value): unknown or missing fields fall
-- back to the defaults.
function Settings.validate(config, raw)
	local settings = Settings.default()
	if type(raw) == "table" and type(raw.view) == "string" and config.views[raw.view] then
		settings.view = raw.view
	end
	return settings
end

function Settings.encode(settings)
	return "view=" .. settings.view .. "\n"
end

-- The settings in `text`; garbage or nil gives the defaults.
function Settings.decode(config, text)
	local raw = {}
	if type(text) == "string" then
		raw.view = text:match("^view=([%w_]+)%s*$")
	end
	return Settings.validate(config, raw)
end

return Settings
