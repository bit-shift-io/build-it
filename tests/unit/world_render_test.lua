-- The world's draw order (src/app/render/world.lua): sprites back to front
-- by depth at their footprint's south-east corner, except the cutaway
-- building (docs/CONTEXT.md "Cutaway"), which sorts by its north-west
-- corner so the figures inside draw over what is left of it.
local WorldRender = require("src.app.render.world")
local Projection = require("src.game.projection")
local Config = require("src.game.config")

local function names(draws)
	local out = {}
	for i, d in ipairs(draws) do
		out[i] = d.name
	end
	return table.concat(out, ",")
end

test("a villager inside the cutaway building draws over it, and inside a whole one under it", function()
	local p = Projection.new(Config, 1, Config.views.topdown)
	local function draws(cut)
		return {
			{ name = "building", sprite = { width = 2, depth = 2 }, tileX = 4, tileY = 4, cutaway = cut },
			{ name = "villager", sprite = { width = 0.5, depth = 0.5 }, tileX = 4.75, tileY = 4.5 },
		}
	end
	local list = draws(true)
	WorldRender.sortDraws(list, p)
	assertEqual("building,villager", names(list))
	list = draws(nil)
	WorldRender.sortDraws(list, p)
	assertEqual("villager,building", names(list))
end)
