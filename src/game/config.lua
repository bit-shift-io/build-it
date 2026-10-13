-- Every tuning number in the game lives here (docs/ARCHITECTURE.md "Rules").
-- Systems and components read it through ctx.config, so a test can pass an
-- override table instead.
return {
	-- Pixels per tile side at zoom 1. One tile is 4x4 studs, 16x16 voxels.
	tileSize = 32,

	-- The world the app opens with, in tiles.
	world = { width = 64, height = 64 },

	character = {
		size = 16, -- placeholder square side, px
		speed = 160, -- walk speed, px/s
	},

	camera = {
		minZoom = 0.25,
		maxZoom = 4,
		zoomStep = 1.1, -- zoom factor per wheel notch
	},
}
