-- Baked prop sprites (docs/CONTEXT.md "Prop"), one atlas per (kind, bake
-- scale, view), cached in the save directory so later launches skip baking.
--
-- Files, under config.props.cacheDir in the save directory:
--   <kind>_v<version>_x<scale>.png   the atlas
--   <kind>_v<version>_x<scale>.txt   one line per sprite:
--     variant stage x y w h anchorX anchorY pixelsPerTile width depth
-- Views other than 3/4 top-down add a suffix: <kind>_v<version>_x<scale>_<view>.*
-- The generator version is in the name, so bumping one kind's version
-- misses its cache (and removes the stale files) without touching others.
--
-- Atlas pixels are premultiplied: draw them with
-- setBlendMode("alpha", "premultiplied"), like any baked sprite.
local Registry = require("src.game.props.registry")
local Baker = require("src.app.bake.baker")

local PropCache = {}

local DEFAULT_VIEW = "topdown"

local PADDING = 2 -- clear pixels around each sprite, so filtering never bleeds

-- kinds: { [name] = <Registry kind> } (normally Registry.KINDS, or
-- { character = Registry.CHARACTER, villager = Registry.villager(config) }
-- for the character's and villagers' frames, which share the cache
-- directory; the villager's shirt colour is hashed into its version). A kind's variant count is Registry.variants.
-- cache.baked lists every "<kind>@<scale>" atlas this cache had to bake, with
-- "@<view>" appended for views other than 3/4 top-down.
function PropCache.new(kinds, config)
	return { kinds = kinds, config = config, dir = config.props.cacheDir, atlases = {}, baked = {} }
end

local function viewSuffix(viewName)
	return viewName == DEFAULT_VIEW and "" or "_" .. viewName
end

local function baseName(def, scale, viewName)
	return def.kind .. "_v" .. def.version .. "_x" .. scale .. viewSuffix(viewName)
end

local function spriteCount(cache, def)
	return Registry.variants(def, cache.config) * def.stages
end

local function newSprite(image, atlasW, atlasH, s)
	return {
		image = image,
		quad = love.graphics.newQuad(s.x, s.y, s.w, s.h, atlasW, atlasH),
		frame = { width = s.w, height = s.h, anchorX = s.anchorX, anchorY = s.anchorY, pixelsPerTile = s.pixelsPerTile },
		width = s.width,
		depth = s.depth,
	}
end

-- { sprites = { [variant] = { [stage] = sprite } } } over one image.
local function atlasOf(image, entries)
	local atlas = { image = image, sprites = {} }
	local w, h = image:getPixelDimensions()
	for _, s in ipairs(entries) do
		atlas.sprites[s.variant] = atlas.sprites[s.variant] or {}
		atlas.sprites[s.variant][s.stage] = newSprite(image, w, h, s)
	end
	return atlas
end

local FIELDS = { "variant", "stage", "x", "y", "w", "h", "anchorX", "anchorY", "pixelsPerTile", "width", "depth" }

local function readEntries(path)
	local text = love.filesystem.read(path)
	if not text then
		return nil
	end
	local entries = {}
	for line in text:gmatch("[^\n]+") do
		local entry, i = {}, 0
		for n in line:gmatch("%-?%d+") do
			i = i + 1
			entry[FIELDS[i] or "extra"] = tonumber(n)
		end
		if i ~= #FIELDS then
			return nil
		end
		entries[#entries + 1] = entry
	end
	return entries
end

local function writeEntries(path, entries)
	local lines = {}
	for _, e in ipairs(entries) do
		local values = {}
		for i, f in ipairs(FIELDS) do
			values[i] = string.format("%d", e[f])
		end
		lines[#lines + 1] = table.concat(values, " ")
	end
	assert(love.filesystem.write(path, table.concat(lines, "\n") .. "\n"))
end

local function load(cache, def, scale, viewName)
	local base = cache.dir .. "/" .. baseName(def, scale, viewName)
	if not love.filesystem.getInfo(base .. ".png") then
		return nil
	end
	local entries = readEntries(base .. ".txt")
	if not entries or #entries ~= spriteCount(cache, def) then
		return nil
	end
	return atlasOf(love.graphics.newImage(base .. ".png"), entries)
end

-- Removes this kind's atlases at this scale and view from other generator
-- versions.
local function removeStale(cache, def, scale, viewName)
	local pattern = "^" .. def.kind .. "_v(%d+)_x" .. scale .. viewSuffix(viewName) .. "%.%a+$"
	for _, name in ipairs(love.filesystem.getDirectoryItems(cache.dir)) do
		local version = name:match(pattern)
		if version and tonumber(version) ~= def.version then
			love.filesystem.remove(cache.dir .. "/" .. name)
		end
	end
end

-- Bakes every variant and stage, packs them one shelf per stage, writes the
-- atlas and its entries to the cache, and returns the atlas.
local function bake(cache, def, scale, viewName)
	local config = cache.config
	local view = config.views[viewName]
	local entries, baked = {}, {}
	local x, y, shelfHeight, atlasW = PADDING, PADDING, 0, 0
	for stage = 1, def.stages do
		for variant = 1, Registry.variants(def, config) do
			local sprite = Baker.bake(Registry.model(def, variant, stage, config), "N", config, scale, view)
			local f = sprite.frame
			entries[#entries + 1] = {
				variant = variant,
				stage = stage,
				x = x,
				y = y,
				w = f.width,
				h = f.height,
				anchorX = f.anchorX,
				anchorY = f.anchorY,
				pixelsPerTile = f.pixelsPerTile,
				width = sprite.width,
				depth = sprite.depth,
			}
			baked[#baked + 1] = sprite
			x = x + f.width + PADDING
			shelfHeight = math.max(shelfHeight, f.height)
		end
		atlasW = math.max(atlasW, x)
		x, y, shelfHeight = PADDING, y + shelfHeight + PADDING, 0
	end

	-- One pixel per unit, whatever the window's DPI scale.
	local atlas = love.graphics.newCanvas(atlasW, y, { dpiscale = 1 })
	love.graphics.push("all")
	love.graphics.origin()
	love.graphics.setCanvas(atlas)
	love.graphics.clear(0, 0, 0, 0)
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.setBlendMode("replace", "premultiplied")
	for i, sprite in ipairs(baked) do
		love.graphics.draw(sprite.image, entries[i].x, entries[i].y)
	end
	love.graphics.pop()
	for _, sprite in ipairs(baked) do
		sprite.image:release()
	end

	local base = cache.dir .. "/" .. baseName(def, scale, viewName)
	love.filesystem.createDirectory(cache.dir)
	removeStale(cache, def, scale, viewName)
	assert(love.filesystem.write(base .. ".png", love.graphics.readbackTexture(atlas):encode("png")))
	writeEntries(base .. ".txt", entries)
	table.insert(cache.baked, def.kind .. "@" .. scale .. (viewName == DEFAULT_VIEW and "" or "@" .. viewName))
	return atlasOf(atlas, entries)
end

-- The baked sprite of a kind's variant at a stage and whole bake scale
-- (Projection.bakeScale):
--   { image = <atlas>, quad, frame = <Projection.spriteFrame>, width, depth }
-- Loads the kind's atlas at that scale and view (a config.views key, default
-- "topdown") from the cache, baking it first on a miss.
function PropCache.sprite(cache, kind, variant, stage, scale, viewName)
	viewName = viewName or DEFAULT_VIEW
	assert(cache.config.views[viewName], "unknown view " .. tostring(viewName))
	local key = kind .. "@" .. scale .. viewSuffix(viewName)
	local atlas = cache.atlases[key]
	if not atlas then
		local def = assert(cache.kinds[kind], "unknown prop kind " .. tostring(kind))
		atlas = load(cache, def, scale, viewName) or bake(cache, def, scale, viewName)
		cache.atlases[key] = atlas
	end
	return atlas.sprites[variant][stage]
end

return PropCache
