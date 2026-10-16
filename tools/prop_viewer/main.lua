-- Dev-only prop viewer: `love12 . props`. Shows every variant (columns) and
-- stage (rows) of one prop kind in a grid. Left/Right switch kind, R reloads
-- the generator source and rebakes. Bakes directly, no disk cache, so R is
-- always fresh. App-level dev tool, so it may use love.*.
local Config = require("src.game.config")

local Viewer = {}

local KIND_ORDER = { "tree", "rock", "character" }
local GAP = 6
local SCALE = 1

local function reloadGenerators()
	for name in pairs(package.loaded) do
		if name:match("^src%.game%.props%.") then
			package.loaded[name] = nil
		end
	end
end

local function defOf(Registry, name)
	return name == "character" and Registry.CHARACTER or Registry.KINDS[name]
end

local function bakeAll(viewer)
	local Registry = require("src.game.props.registry")
	local Baker = require("src.app.bake.baker")
	local def = defOf(Registry, viewer.kinds[viewer.index])
	local variants = Registry.variants(def, viewer.config)
	viewer.sprites = {}
	viewer.columns, viewer.rows = variants, def.stages
	for stage = 1, def.stages do
		for variant = 1, variants do
			local model = Registry.model(def, variant, stage, viewer.config)
			viewer.sprites[#viewer.sprites + 1] =
				{ sprite = Baker.bake(model, "N", viewer.config, SCALE), variant = variant, stage = stage }
		end
	end
end

function Viewer.new(config)
	local viewer = { config = config or Config, kinds = KIND_ORDER, index = 1 }
	bakeAll(viewer)
	return viewer
end

function Viewer.kind(viewer)
	return viewer.kinds[viewer.index]
end

-- Number of baked sprites on show (variants x stages of the current kind).
function Viewer.spriteCount(viewer)
	return #viewer.sprites
end

-- Re-reads generator source from disk and rebakes the current kind.
function Viewer.reload(viewer)
	reloadGenerators()
	package.loaded["src.game.props.registry"] = nil
	bakeAll(viewer)
end

function Viewer.keypressed(viewer, key)
	if key == "r" then
		Viewer.reload(viewer)
	elseif key == "right" or key == "left" then
		local n = #viewer.kinds
		viewer.index = (viewer.index - 1 + (key == "right" and 1 or -1)) % n + 1
		bakeAll(viewer)
	end
end

function Viewer.draw(viewer)
	local cellW, cellH = 0, 0
	for _, s in ipairs(viewer.sprites) do
		cellW = math.max(cellW, s.sprite.frame.width)
		cellH = math.max(cellH, s.sprite.frame.height)
	end
	cellW, cellH = cellW + GAP, cellH + GAP
	love.graphics.push("all")
	love.graphics.clear(0.3, 0.3, 0.3, 1)
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.print(
		string.format("%s  (%d variants x %d stages)  Left/Right: kind  R: reload", Viewer.kind(viewer), viewer.columns, viewer.rows),
		GAP,
		GAP
	)
	love.graphics.setBlendMode("alpha", "premultiplied")
	for _, s in ipairs(viewer.sprites) do
		love.graphics.draw(s.sprite.image, GAP + (s.variant - 1) * cellW, 30 + (s.stage - 1) * cellH)
	end
	love.graphics.pop()
end

-- Takes over the LÖVE callbacks; called from main.lua for the `props` arg.
function Viewer.start()
	local viewer = Viewer.new(Config)
	Viewer.instance = viewer
	function love.keypressed(key)
		Viewer.keypressed(viewer, key)
	end
	function love.update() end
	function love.draw()
		Viewer.draw(viewer)
	end
	return viewer
end

return Viewer
