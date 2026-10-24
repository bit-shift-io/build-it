-- Which building draws cut away (docs/CONTEXT.md "Cutaway"): only the one
-- whose footprint holds the player's centre. Baking itself is e2e.
local BuildingsRender = require("src.app.render.buildings")
local Config = require("src.game.config")

local TILE = Config.tileSize

local function ctx(px, py)
	return {
		config = Config,
		pools = {
			characters = { { x = px, y = py } },
			buildings = {
				{ tileX = 2, tileY = 2, width = 3, depth = 2 },
				{ tileX = 6, tileY = 2, width = 1, depth = 1 },
			},
		},
	}
end

test("the building under the player's centre is the one cut away", function()
	local c = ctx(4.5 * TILE, 3.9 * TILE)
	assertEqual(c.pools.buildings[1], BuildingsRender.cutawayOf(c))
	c = ctx(6.5 * TILE, 2.5 * TILE)
	assertEqual(c.pools.buildings[2], BuildingsRender.cutawayOf(c))
end)

test("outside every footprint nothing is cut away", function()
	assertEqual(nil, BuildingsRender.cutawayOf(ctx(5.5 * TILE, 2.5 * TILE)), "between the two")
	assertEqual(nil, BuildingsRender.cutawayOf(ctx(4.5 * TILE, 4 * TILE)), "on the south edge, just out")
end)
