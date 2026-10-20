-- The world screen: the character walking the tile world, the camera
-- following it, the wheel zooming it.
--
-- Right-clicking the world opens a context menu with "Build"; that, or the
-- 1 key, opens the building picker (src/app/picker.lua), which lists the
-- library's designs and filters them as the player types. Picking one
-- starts placement mode (docs/CONTEXT.md "Building"): a ghost of it follows the
-- pointer, R turns it to the next facing, a left click places it, and Esc
-- or a right click leaves the mode. While placing, left clicks never
-- harvest.
local Session = require("src.game.session")
local CharacterSystem = require("src.game.systems.character_system")
local Placement = require("src.game.buildings.placement")
local Model = require("src.game.blocks.model")
local Cost = require("src.game.builder.cost")
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

local WorldScreen = {}

-- The projection of the screen's active view, at the world's base scale.
local function projectionOf(screen)
	return Projection.new(screen.ctx.config, 1, screen.ctx.config.views[screen.view])
end

-- Centres `camera` on a record at world px (x, y), through the active view.
local function follow(camera, ctx, viewName, x, y)
	local tile = ctx.config.tileSize
	Camera.follow(camera, Projection.new(ctx.config, 1, ctx.config.views[viewName]), x / tile, y / tile)
end

-- library: the design library (src/game/designs/library.lua), shared with
-- the builder. viewName: a config.views key (default "topdown"), the view the
-- world draws in.
function WorldScreen.new(ctx, library, viewName)
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
		-- Placement mode: { design, version, facing }, or nil.
		placing = nil,
		-- The context menu { x, y } while open, or nil.
		menu = nil,
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

-- The ghost of the design being placed, centred on the pointer:
--   { request = { design, version, facing, tileX, tileY }, ok, reason }
-- (Placement.check's answer), or nil when not placing or the pointer has
-- not moved yet.
function WorldScreen.ghost(screen)
	local placing = screen.placing
	if not (placing and screen.mouse) then
		return nil
	end
	local version = placing.design.versions[placing.version]
	local width, depth = Placement.footprint(version, placing.facing)
	local wx, wy = worldAt(screen, screen.mouse.x, screen.mouse.y)
	local request = {
		design = placing.design,
		version = placing.version,
		facing = placing.facing,
		tileX = math.floor(wx - width / 2 + 0.5),
		tileY = math.floor(wy - depth / 2 + 0.5),
	}
	local ok, reason = Placement.check(screen.ctx, request)
	return { request = request, ok = ok, reason = reason }
end

local NEXT_FACING = {}
for i, facing in ipairs(Model.FACINGS) do
	NEXT_FACING[facing] = Model.FACINGS[i % #Model.FACINGS + 1]
end

-- Whether a menu or the picker has the keyboard and pointer.
function WorldScreen.modal(screen)
	return screen.menu ~= nil or screen.picker ~= nil or screen.settings ~= nil
end

-- Closes the menu, the picker and the settings overlay.
local function closeModal(screen)
	screen.menu, screen.picker, screen.dropText, screen.settings = nil, nil, nil, nil
end

-- Opens the settings overlay, over the paused or running world.
local function openSettings(screen)
	closeModal(screen)
	screen.pointer = nil
	screen.settings = SettingsScreen.new(screen.ctx.config, screen.view)
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

-- Opens the building picker; `key` is the key that opened it, if any.
local function openPicker(screen, key)
	closeModal(screen)
	screen.picker = Picker.new(Library.liveDesigns(screen.library))
	screen.pointer = nil
	screen.dropText = key
end

-- Starts placing `design` (its latest version).
local function pick(screen, design)
	closeModal(screen)
	screen.placing = { design = design, version = Library.newestLive(design), facing = "N" }
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
	else
		screen.message = WorldScreen.reasonText(ghost.reason)
	end
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
			if screen.settings.choice then
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
		if button == 1 and PickerRender.menuHit(screen.menu, x, y) then
			openPicker(screen, nil)
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
		screen.menu = { x = x, y = y }
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
	WorldRender.draw(screen.ctx, screen.camera.zoom, screen.view)
	CharacterRender.draw(screen.ctx, screen.camera.zoom, screen.view)
	if ghost then
		GhostRender.draw(screen.ctx, ghost, screen.camera.zoom, screen.view)
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
		PickerRender.drawPicker(screen.picker, screen.mouse, { config = screen.ctx.config, totals = StorageFacility.totals(screen.ctx) })
	end
end

-- What the design being placed costs, or nil when not placing.
function WorldScreen.cost(screen)
	local placing = screen.placing
	return placing and Cost.of(placing.design.versions[placing.version], screen.ctx.config)
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
