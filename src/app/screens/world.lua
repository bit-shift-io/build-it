-- The world screen: the character walking the tile world, the camera
-- following it, the wheel zooming it.
local Session = require("src.game.session")
local Input = require("src.app.input")
local Camera = require("src.app.camera")
local Screen = require("src.app.screen")
local WorldRender = require("src.app.render.world")
local CharacterRender = require("src.app.render.character")
local Hud = require("src.app.render.hud")
local Projection = require("src.game.projection")

local WorldScreen = {}

function WorldScreen.new(ctx)
	local player = ctx.pools.characters[1]
	return { ctx = ctx, player = player, camera = Camera.new(player.x, player.y) }
end

-- The tile under the held left-click pointer, or nil when not held.
local function pointerTile(screen)
	local pointer = screen.pointer
	if not pointer then
		return nil
	end
	local w, h = Screen.dimensions()
	local cam = screen.camera
	local px = cam.x + (pointer.x - w / 2) / cam.zoom
	local py = cam.y + (pointer.y - h / 2) / cam.zoom
	local tx, ty = Projection.screenToWorld(Projection.new(screen.ctx.config), px, py, 0)
	return { x = math.floor(tx), y = math.floor(ty) }
end

-- Holding the left button on a tile harvests the node there.
function WorldScreen.mousepressed(screen, x, y, button)
	if button == 1 then
		screen.pointer = { x = x, y = y }
	end
end

function WorldScreen.mousemoved(screen, x, y)
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
	Input.updateIntents(screen.ctx, pointerTile(screen))
	Session.advance(screen.ctx, dt)
	Camera.follow(screen.camera, screen.player.x, screen.player.y)
end

function WorldScreen.wheelmoved(screen, _, y)
	Camera.zoomBy(screen.camera, y, screen.ctx.config.camera)
end

function WorldScreen.draw(screen)
	Camera.attach(screen.camera, Screen.dimensions())
	WorldRender.draw(screen.ctx, screen.camera.zoom)
	CharacterRender.draw(screen.ctx)
	Camera.detach()
	Hud.draw(screen.player.inventory)
end

return WorldScreen
