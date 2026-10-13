local TestHouse = require("src.game.blocks.test_house")
local Model = require("src.game.blocks.model")
local Config = require("src.game.config")

test("TestHouse.placements puts one house per facing on whole tiles inside the world", function()
	local world = { width = 40, height = 30 }
	local placements = TestHouse.placements(world, Config)
	assertEqual(4, #placements)
	for i, p in ipairs(placements) do
		assertEqual(Model.FACINGS[i], p.facing)
		assertEqual(math.floor(p.tileX), p.tileX)
		assertEqual(math.floor(p.tileY), p.tileY)
		assertTrue(p.tileX >= 0 and p.tileX + 3 <= world.width, "house inside the world east-west")
		assertTrue(p.tileY >= 0 and p.tileY + 3 <= world.height, "house inside the world north-south")
	end
end)
