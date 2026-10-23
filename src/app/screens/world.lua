-- The world screen: the character walking the tile world, the camera
-- following it, the wheel zooming it.
--
-- Right-clicking the world opens a context menu with "Build"; that, or the
-- 1 key, opens the building picker (src/app/picker.lua), which lists the
-- library's placeable designs (Library.placeable: compiled, with a function
-- role) and filters them as the player types. Picking one starts placement
-- mode with its blueprint (docs/CONTEXT.md "Building"): a ghost of it follows the
-- pointer, R turns it to the next facing, a left click places it, and Esc
-- or a right click leaves the mode. While placing, left clicks never
-- harvest.
--
-- Right-clicking a building adds "Replace..." to the menu (docs/CONTEXT.md
-- "Replace"): it opens the picker, and the chosen design's ghost sits
-- centred on that building with its facing, whatever the pointer does; R
-- turns it and a left click confirms.
local Session = require("src.game.session")
local CharacterSystem = require("src.game.systems.character_system")
local Placement = require("src.game.buildings.placement")
local Input = require("src.app.input")
local Camera = require("src.app.camera")
local Screen = require("src.app.screen")
local WorldRender = require("src.app.render.world")
local CharacterRender = require("src.app.render.character")
local Library = require("src.game.designs.library")
local GhostRender = require("src.app.render.ghost")
local Aura = require("src.game.components.aura")
local StorageFacility = require("src.game.components.storage_facility")
local Hud = require("src.app.render.hud")
local Projection = require("src.game.projection")
local Status = require("src.game.components.status")
local Card = require("src.app.render.card")
local Picker = require("src.app.picker")
local PickerRender = require("src.app.render.picker")
local SettingsScreen = require("src.app.screens.settings")
local Palette = require("src.game.palette")
local World = require("src.game.world")
local Compile = require("src.game.buildings.compile")

local WorldScreen = {}

local drawBadges

-- The projection of the screen's active view, at the world's base scale.
local function projectionOf(screen)
	return Projection.new(screen.ctx.config, 1, screen.ctx.config.views[screen.view])
end

-- Centres `camera` on a record at world px (x, y), through the active view.
local function follow(camera, ctx, viewName, x, y)
	local tile = ctx.config.tileSize
	Camera.follow(camera, Projection.new(ctx.config, 1, ctx.config.views[viewName]), x / tile, y / tile)
end

-- library(): the design library (src/game/designs/library.lua) as it is
-- now, read afresh each time the picker opens. viewName: a config.views key
-- (default "topdown"), the view the world draws in. colours: the local
-- player's team colours, { primary, secondary } (default Palette's).
function WorldScreen.new(ctx, library, viewName, colours)
	colours = colours or { primary = Palette.DEFAULT_PRIMARY, secondary = Palette.DEFAULT_SECONDARY }
	local player = ctx.pools.characters[1]
	viewName = viewName or "topdown"
	local camera = Camera.new()
	follow(camera, ctx, viewName, player.x, player.y)
	return {
		ctx = ctx,
		view = viewName,
		player = player,
		camera = camera,
		library = library,
		-- The pointer's last screen position, once it has moved.
		mouse = nil,
		-- Placement mode: { design = <name>, blueprint, facing, replaces? },
		-- or nil. `replaces`: the building a Replace... turns into a site.
		placing = nil,
		-- The context menu { x, y, building? } while open, or nil;
		-- `building` when it was opened on one.
		menu = nil,
		-- The building the open picker's pick will replace, or nil.
		replacing = nil,
		-- The library's designs as compiled now, for the changed-design
		-- badge: { [name] = hash | false } (false: it doesn't compile or is
		-- gone), filled as buildings ask, emptied by WorldScreen.refresh;
		-- and the library they compile against.
		designHashes = {},
		designLibrary = nil,
		-- The building picker's state (src/app/picker.lua) while open, or nil.
		picker = nil,
		-- Set when a key opened the picker: that key's own textinput, which
		-- follows its keypressed, must not be typed into the search.
		dropText = nil,
		-- A placement request clicked this step, for the next intents.
		pendingPlace = nil,
		-- Why the last placement was refused, or nil.
		message = nil,
		-- True while P has paused the session. Hover, placement and the
		-- camera zoom keep working; only the simulation stops.
		paused = false,
		-- The settings overlay (SettingsScreen state) while open, or nil.
		settings = nil,
		-- The view name picked in the overlay, until the flow saves it.
		viewChoice = nil,
		-- The team colours buildings draw in, and the last one picked in
		-- the overlay ({ field, color }) until the flow saves it.
		colours = { primary = colours.primary, secondary = colours.secondary },
		colourChoice = nil,
		-- Their team palette (Palette.derive), remade when one changes.
		palette = Palette.derive(colours.primary, colours.secondary),
		-- Views drawn at least once (their bakes are done).
		drawn = {},
		-- True for the one draw after a switch to an unbaked view: it shows
		-- "Baking..." so the bake on the following draw has a message up.
		baking = false,
	}
end

-- The view-space pixel (world drawing coordinates) under window pixel (x, y).
local function viewPoint(screen, x, y)
	local w, h = Screen.dimensions()
	local cam = screen.camera
	return cam.x + (x - w / 2) / cam.zoom, cam.y + (y - h / 2) / cam.zoom
end

-- The world point (tiles, at ground level) under window pixel (x, y).
local function worldAt(screen, x, y)
	local px, py = viewPoint(screen, x, y)
	return Projection.screenToWorld(projectionOf(screen), px, py, 0)
end

-- The villager or player whose sprite is under the pointer, or nil. Tests
-- the sprite's screen rect, not the tile under the pointer.
function WorldScreen.hovered(screen)
	if not screen.mouse or screen.placing or screen.menu or screen.picker then
		return nil
	end
	local px, py = viewPoint(screen, screen.mouse.x, screen.mouse.y)
	return CharacterRender.at(screen.ctx, px, py, screen.view)
end

-- The tile under the held left-click pointer, or nil when not held.
local function pointerTile(screen)
	local pointer = screen.pointer
	if not pointer then
		return nil
	end
	local tx, ty = worldAt(screen, pointer.x, pointer.y)
	return { x = math.floor(tx), y = math.floor(ty) }
end

-- The ghost of the design being placed, centred on the pointer, or on the
-- building it replaces:
--   { request = { design, blueprint, facing, tileX, tileY, replaces? },
--     ok, reason }
-- (Placement.check's answer), or nil when not placing or the pointer has
-- not moved yet.
function WorldScreen.ghost(screen)
	local placing = screen.placing
	local old = placing and placing.replaces
	if not (placing and (screen.mouse or old)) then
		return nil
	end
	local width, depth = Placement.footprint(placing.blueprint, placing.facing)
	local wx, wy
	if old then
		wx, wy = old.tileX + old.width / 2, old.tileY + old.depth / 2
	else
		wx, wy = worldAt(screen, screen.mouse.x, screen.mouse.y)
	end
	local request = {
		design = placing.design,
		blueprint = placing.blueprint,
		facing = placing.facing,
		tileX = math.floor(wx - width / 2 + 0.5),
		tileY = math.floor(wy - depth / 2 + 0.5),
		replaces = old,
	}
	local ok, reason = Placement.check(screen.ctx, request)
	return { request = request, ok = ok, reason = reason }
end

local NEXT_FACING = {}
for i, facing in ipairs(Placement.FACINGS) do
	NEXT_FACING[facing] = Placement.FACINGS[i % #Placement.FACINGS + 1]
end

-- Whether a menu or the picker has the keyboard and pointer.
function WorldScreen.modal(screen)
	return screen.menu ~= nil or screen.picker ~= nil or screen.settings ~= nil
end

-- Closes the menu, the picker and the settings overlay.
local function closeModal(screen)
	screen.menu, screen.picker, screen.dropText, screen.settings = nil, nil, nil, nil
	screen.replacing = nil
end

-- Opens the settings overlay, over the paused or running world.
local function openSettings(screen)
	closeModal(screen)
	screen.pointer = nil
	screen.settings = SettingsScreen.new(screen.ctx.config, screen.view, screen.colours)
end

-- Shows the world in view `name`, live: the camera re-centres on the player
-- and keeps its zoom. A view not yet drawn gets a "Baking..." frame first.
-- The flow saves screen.viewChoice.
local function switchView(screen, name)
	closeModal(screen)
	if name == screen.view then
		return
	end
	screen.view = name
	screen.viewChoice = name
	screen.baking = not screen.drawn[name]
	follow(screen.camera, screen.ctx, name, screen.player.x, screen.player.y)
end

-- Forgets the compiled designs, so the badges follow the library as it is
-- now (`library`, when the caller just read it). The flow calls it on the
-- way back from the builder; the picker on every open.
function WorldScreen.refresh(screen, library)
	screen.designHashes = {}
	screen.designLibrary = library
end

-- Whether building `b`'s design file changed since its blueprint was
-- frozen (ADR 0007): the design compiles to another blueprint now. False
-- for a design that is gone or doesn't compile.
function WorldScreen.changed(screen, b)
	local hashes = screen.designHashes
	if hashes[b.design] == nil then
		screen.designLibrary = screen.designLibrary or screen.library()
		local lib = screen.designLibrary
		local text = lib.designs[b.design]
		local blueprint = text and Compile.design(text, b.design, lib, screen.ctx.config)
		hashes[b.design] = blueprint and blueprint.hash or false
	end
	return hashes[b.design] ~= false and hashes[b.design] ~= b.blueprint.hash
end

-- Opens the building picker; `key` is the key that opened it, if any.
-- `replacing`: the building the pick will replace, if any.
local function openPicker(screen, key, replacing)
	closeModal(screen)
	screen.replacing = replacing
	local library = screen.library()
	WorldScreen.refresh(screen, library)
	screen.picker = Picker.new(Library.placeable(library, screen.ctx.config))
	screen.pointer = nil
	screen.dropText = key
end

-- Starts placing `design` (a picker entry: { name, blueprint }), its
-- blueprint frozen from here on; as a replacement when the picker was
-- opened by Replace..., with the old building's facing.
local function pick(screen, design)
	local old = screen.replacing
	closeModal(screen)
	screen.placing = { design = design.name, blueprint = design.blueprint, facing = old and old.facing or "N", replaces = old }
	screen.message = nil
end

local function stopPlacing(screen)
	screen.placing = nil
	screen.message = nil
end

function WorldScreen.keypressed(screen, key)
	if screen.settings then
		if key == "o" or key == "escape" then
			closeModal(screen)
		else
			SettingsScreen.keypressed(screen.settings, key)
			if screen.settings.choice then
				switchView(screen, screen.settings.choice)
			end
		end
	elseif key == "o" and not screen.picker and not screen.menu then
		openSettings(screen)
	elseif key == "p" and not screen.picker then
		screen.paused = not screen.paused
	elseif key == "1" then
		openPicker(screen, key)
	elseif screen.picker then
		if key == "backspace" then
			Picker.backspace(screen.picker)
		elseif key == "return" or key == "kpenter" then
			local first = Picker.matches(screen.picker)[1]
			if first then
				pick(screen, first)
			end
		elseif key == "escape" then
			closeModal(screen)
		end
	elseif screen.menu then
		if key == "escape" then
			closeModal(screen)
		end
	elseif screen.placing and key == "r" then
		screen.placing.facing = NEXT_FACING[screen.placing.facing]
	elseif screen.placing and key == "escape" then
		stopPlacing(screen)
	end
end

-- Placement.check's reasons, for the player.
local REASONS = {
	outside = "it would stand outside the world",
	water = "it would stand on water",
	node = "a tree or rock is in the way",
	building = "another building is in the way",
	["port blocked"] = "a port tile is blocked",
	unaffordable = "not enough materials",
	gone = "that building is already being replaced",
	["storage facility"] = "a storage facility can't be replaced",
}

-- Why `reason` (Placement.check's) refuses a placement, for the player.
function WorldScreen.reasonText(reason)
	return "Can't place: " .. (REASONS[reason] or reason)
end

-- Places the ghost when it is valid; otherwise says why not.
local function placeGhost(screen)
	local ghost = WorldScreen.ghost(screen)
	if not ghost then
		return
	end
	if ghost.ok then
		screen.pendingPlace = ghost.request
		screen.message = nil
		if ghost.request.replaces then
			-- A building is replaced once.
			stopPlacing(screen)
		end
	else
		screen.message = WorldScreen.reasonText(ghost.reason)
	end
end

-- The finished building under window pixel (x, y) (not a construction
-- site), or nil.
local function buildingAt(screen, x, y)
	local tx, ty = worldAt(screen, x, y)
	local b = World.buildingAt(screen.ctx.world, math.floor(tx), math.floor(ty))
	for _, building in ipairs(screen.ctx.pools.buildings) do
		if building == b and not b.dead then
			return b
		end
	end
	return nil
end

-- Whether window pixel (x, y) is on the Settings button.
local function overSettingsButton(x, y)
	local b = Hud.settingsButton((Screen.dimensions()))
	return x >= b.x and x < b.x + b.width and y >= b.y and y < b.y + b.height
end

-- Holding the left button on a tile harvests the node there, unless
-- placing.
function WorldScreen.mousepressed(screen, x, y, button)
	screen.mouse = { x = x, y = y }
	if screen.settings then
		if button == 1 then
			SettingsScreen.mousepressed(screen.settings, x, y, button)
			local picked = screen.settings.colourChoice
			if picked then
				-- A team colour: the overlay stays open on it.
				screen.settings.colourChoice = nil
				screen.colours[picked.field] = picked.color
				screen.palette = Palette.derive(screen.colours.primary, screen.colours.secondary)
				screen.colourChoice = picked
			elseif screen.settings.choice then
				switchView(screen, screen.settings.choice)
			else
				closeModal(screen)
			end
		else
			closeModal(screen)
		end
	elseif screen.picker then
		if button == 2 then
			closeModal(screen)
		elseif button == 1 then
			local w, h = Screen.dimensions()
			local design = PickerRender.designAt(screen.picker, w, h, x, y)
			if design then
				pick(screen, design)
			end
		end
	elseif screen.menu then
		local entry = button == 1 and PickerRender.menuAt(screen.menu, x, y)
		if entry == "build" then
			openPicker(screen, nil)
		elseif entry == "replace" then
			openPicker(screen, nil, screen.menu.building)
		else
			closeModal(screen)
		end
	elseif button == 1 and overSettingsButton(x, y) then
		openSettings(screen)
	elseif screen.placing then
		if button == 1 then
			placeGhost(screen)
		elseif button == 2 then
			stopPlacing(screen)
		end
	elseif button == 2 then
		screen.menu = { x = x, y = y, building = buildingAt(screen, x, y) }
		screen.pointer = nil
	elseif button == 1 then
		screen.pointer = { x = x, y = y }
	end
end

-- Typed text goes to the picker's search.
function WorldScreen.textinput(screen, text)
	if not screen.picker then
		return
	end
	if screen.dropText == text then
		screen.dropText = nil
		return
	end
	Picker.type(screen.picker, text)
end

function WorldScreen.mousemoved(screen, x, y)
	screen.mouse = { x = x, y = y }
	if screen.pointer then
		screen.pointer = { x = x, y = y }
	end
end

function WorldScreen.mousereleased(screen, _, _, button)
	if button == 1 then
		screen.pointer = nil
	end
end

-- One fixed step: read devices, step the session, follow the player. Does
-- nothing while paused.
function WorldScreen.update(screen, dt)
	if screen.paused then
		return
	end
	Input.updateIntents(screen.ctx, pointerTile(screen), screen.pendingPlace, WorldScreen.modal(screen), screen.ctx.config.views[screen.view])
	screen.pendingPlace = nil
	screen.dropText = nil
	Session.advance(screen.ctx, dt)
	follow(screen.camera, screen.ctx, screen.view, screen.player.x, screen.player.y)
end

function WorldScreen.wheelmoved(screen, _, y)
	if screen.settings then
		return
	elseif screen.picker then
		Picker.scrollBy(screen.picker, -y)
		return
	end
	Camera.zoomBy(screen.camera, y, screen.ctx.config.camera)
end

-- The team palette buildings draw in: the local player's (one player
-- today), from screen.colours.
function WorldScreen.palette(screen)
	return screen.palette
end

local BADGE = { 0.95, 0.75, 0.2, 1 }

-- A badge on the north-east ground corner of each building whose design
-- file changed since it was placed (WorldScreen.changed): replacing it with
-- the same design applies the edit.
function drawBadges(screen)
	local p = projectionOf(screen)
	love.graphics.push("all")
	for _, b in ipairs(screen.ctx.pools.buildings) do
		if not b.dead and WorldScreen.changed(screen, b) then
			local x, y = Projection.worldToScreen(p, b.tileX + b.width - 0.25, b.tileY + 0.25, 0)
			love.graphics.setColor(0, 0, 0, 0.8)
			love.graphics.circle("fill", x, y, 7)
			love.graphics.setColor(BADGE)
			love.graphics.circle("fill", x, y, 5)
			love.graphics.setColor(0, 0, 0, 1)
			love.graphics.print("!", x - 2, y - 7)
		end
	end
	love.graphics.pop()
end

function WorldScreen.draw(screen)
	if screen.baking then
		-- The "Baking..." frame; the next draw bakes the new view.
		screen.baking = false
		local w, h = Screen.dimensions()
		Hud.drawBaking(w, h)
		return
	end
	screen.drawn[screen.view] = true
	local ghost = WorldScreen.ghost(screen)
	Camera.attach(screen.camera, Screen.dimensions())
	local palette = WorldScreen.palette(screen)
	WorldRender.draw(screen.ctx, screen.camera.zoom, screen.view, palette)
	CharacterRender.draw(screen.ctx, screen.camera.zoom, screen.view)
	drawBadges(screen)
	if ghost then
		GhostRender.draw(screen.ctx, ghost, screen.camera.zoom, screen.view, palette)
	end
	Camera.detach()
	Hud.draw(screen.player.inventory, StorageFacility.totals(screen.ctx), CharacterSystem.portInUse(screen.player, screen.ctx), Aura.at(screen.ctx, screen.player), StorageFacility.claimed(screen.ctx), StorageFacility.totalFill(screen.ctx), Status.hunger(screen.player.needs, screen.ctx.config.needs), screen.ctx.config.food)
	local hovered = WorldScreen.hovered(screen)
	if hovered then
		Card.draw(Status.lines(hovered, Aura.at(screen.ctx, hovered)), screen.mouse.x, screen.mouse.y, Status.bars(hovered))
	end
	Hud.drawSettingsButton((Screen.dimensions()), screen.mouse)
	GhostRender.drawPanel(screen.placing, WorldScreen.cost(screen), WorldScreen.status(screen), StorageFacility.totals(screen.ctx))
	if screen.settings then
		local w, h = Screen.dimensions()
		love.graphics.setColor(0, 0, 0, 0.6)
		love.graphics.rectangle("fill", 0, 0, w, h)
		love.graphics.setColor(1, 1, 1, 1)
		SettingsScreen.draw(screen.settings)
	elseif screen.menu then
		PickerRender.drawMenu(screen.menu, screen.mouse)
	elseif screen.picker then
		PickerRender.drawPicker(screen.picker, screen.mouse, { config = screen.ctx.config, totals = StorageFacility.totals(screen.ctx), palette = palette })
	end
end

-- What placing the design costs (for a replacement, only the missing
-- materials: Placement.cost), or nil when not placing.
function WorldScreen.cost(screen)
	local placing = screen.placing
	return placing and Placement.cost(placing)
end

-- Why the ghost may not be placed (or the last refusal), for the player;
-- nil when it may.
function WorldScreen.status(screen)
	local ghost = WorldScreen.ghost(screen)
	if ghost and not ghost.ok then
		return WorldScreen.reasonText(ghost.reason)
	end
	return screen.message
end

return WorldScreen
