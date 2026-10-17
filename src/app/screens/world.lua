-- The world screen: the character walking the tile world, the camera
-- following it, the wheel zooming it.
--
-- Placement mode (docs/CONTEXT.md "Building"): number keys 1-9 pick that
-- design of the library (its latest version); a ghost of it follows the
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

-- Starts placing library design number `n` (its latest version).
local function pick(screen, n)
	local design = Library.liveDesigns(screen.library)[n]
	if not design then
		screen.message = "No design " .. n .. " in the library."
		return
	end
	screen.placing = { design = design, version = Library.newestLive(design), facing = "N" }
	screen.message = nil
end

local function stopPlacing(screen)
	screen.placing = nil
	screen.message = nil
end

function WorldScreen.keypressed(screen, key)
	local n = tonumber(key)
	if n and n >= 1 and n <= 9 then
		pick(screen, n)
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
	if screen.placing then
		if button == 1 then
			placeGhost(screen)
		elseif button == 2 then
			stopPlacing(screen)
		end
	elseif button == 1 then
		screen.pointer = { x = x, y = y }
	end
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
	Input.updateIntents(screen.ctx, pointerTile(screen), screen.pendingPlace)
	screen.pendingPlace = nil
	Session.advance(screen.ctx, dt)
	Camera.follow(screen.camera, screen.player.x, screen.player.y)
end

function WorldScreen.wheelmoved(screen, _, y)
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
	Hud.draw(screen.player.inventory, StorageFacility.totals(screen.ctx), CharacterSystem.outputPortUnder(screen.player, screen.ctx), Aura.at(screen.ctx, screen.player), StorageFacility.claimed(screen.ctx))
	GhostRender.drawPanel(screen.library, screen.placing, WorldScreen.cost(screen), WorldScreen.status(screen))
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
