-- The world screen: the character walking the tile world, the camera
-- following it, the wheel zooming it.
local Session = require("src.game.session")
local Input = require("src.app.input")
local Camera = require("src.app.camera")
local Screen = require("src.app.screen")
local WorldRender = require("src.app.render.world")
local CharacterRender = require("src.app.render.character")

local WorldScreen = {}

function WorldScreen.new(ctx)
	local player = ctx.pools.characters[1]
	return { ctx = ctx, player = player, camera = Camera.new(player.x, player.y) }
end

-- One fixed step: read devices, step the session, follow the player.
function WorldScreen.update(screen, dt)
	Input.updateIntents(screen.ctx)
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
end

return WorldScreen
