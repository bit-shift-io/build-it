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

local WorldScreen = {}

-- library: the design library (src/game/designs/library.lua), shared with
-- the builder.
function WorldScreen.new(ctx, library)
	local player = ctx.pools.characters[1]
	return {
		ctx = ctx,
		player = player,
		camera = Camera.new(player.x, player.y),
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
	}
end

-- The world point (tiles, at ground level) under screen pixel (x, y).
local function worldAt(screen, x, y)
	local w, h = Screen.dimensions()
	local cam = screen.camera
	local px = cam.x + (x - w / 2) / cam.zoom
	local py = cam.y + (y - h / 2) / cam.zoom
	return Projection.screenToWorld(Projection.new(screen.ctx.config), px, py, 0)
end

-- The villager or player whose sprite is under the pointer, or nil. Tests
-- the sprite's screen rect, not the tile under the pointer.
function WorldScreen.hovered(screen)
	if not screen.mouse or screen.placing or screen.menu or screen.picker then
		return nil
	end
	local w, h = Screen.dimensions()
	local cam = screen.camera
	local px = cam.x + (screen.mouse.x - w / 2) / cam.zoom
	local py = cam.y + (screen.mouse.y - h / 2) / cam.zoom
	return CharacterRender.at(screen.ctx, px, py)
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
	return screen.menu ~= nil or screen.picker ~= nil
end

-- Closes the menu and the picker.
local function closeModal(screen)
	screen.menu, screen.picker, screen.dropText = nil, nil, nil
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
	if key == "1" then
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

-- Holding the left button on a tile harvests the node there, unless
-- placing.
function WorldScreen.mousepressed(screen, x, y, button)
	screen.mouse = { x = x, y = y }
	if screen.picker then
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

-- One fixed step: read devices, step the session, follow the player.
function WorldScreen.update(screen, dt)
	Input.updateIntents(screen.ctx, pointerTile(screen), screen.pendingPlace, WorldScreen.modal(screen))
	screen.pendingPlace = nil
	screen.dropText = nil
	Session.advance(screen.ctx, dt)
	Camera.follow(screen.camera, screen.player.x, screen.player.y)
end

function WorldScreen.wheelmoved(screen, _, y)
	if screen.picker then
		Picker.scrollBy(screen.picker, -y)
		return
	end
	Camera.zoomBy(screen.camera, y, screen.ctx.config.camera)
end

function WorldScreen.draw(screen)
	local ghost = WorldScreen.ghost(screen)
	Camera.attach(screen.camera, Screen.dimensions())
	WorldRender.draw(screen.ctx, screen.camera.zoom)
	CharacterRender.draw(screen.ctx, screen.camera.zoom)
	if ghost then
		GhostRender.draw(screen.ctx, ghost, screen.camera.zoom)
	end
	Camera.detach()
	Hud.draw(screen.player.inventory, StorageFacility.totals(screen.ctx), CharacterSystem.portInUse(screen.player, screen.ctx), Aura.at(screen.ctx, screen.player), StorageFacility.claimed(screen.ctx), StorageFacility.totalFill(screen.ctx), Status.hunger(screen.player.needs, screen.ctx.config.needs), screen.ctx.config.food)
	local hovered = WorldScreen.hovered(screen)
	if hovered then
		Card.draw(Status.lines(hovered, Aura.at(screen.ctx, hovered)), screen.mouse.x, screen.mouse.y, Status.bars(hovered))
	end
	GhostRender.drawPanel(screen.placing, WorldScreen.cost(screen), WorldScreen.status(screen), StorageFacility.totals(screen.ctx))
	if screen.menu then
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
