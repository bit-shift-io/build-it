-- Hand harvesting under real LÖVE 12: the HUD counts and a harvested tree
-- (last stage beside a half-felled tree) and rock. Captures land in
-- tests/screenshots/hand_harvest_test/.
local GameHarness = require("tests.support.game_harness")
local Capture = require("tests.support.capture")
local Fake = require("tests.support.fake_input")
local Config = require("src.game.config")
local World = require("src.game.world")
local Inventory = require("src.game.components.inventory")

test("the HUD shows logs, stone and planks after harvesting one tree to its last stage and another to half-felled", function()
	local world = World.new(12, 12)
	local function node(id, kind, x, y)
		return World.addNode(world, { id = id, kind = kind, tileX = x, tileY = y, variant = 1, stage = 1, amount = Config.nodes[kind].amount })
	end
	local last = node(1, "tree", 8, 6)
	local half = node(2, "tree", 6, 8)
	local rock = node(3, "rock", 4, 6)
	local game = GameHarness.startSession(world, { real = true })
	local input = Fake.FakeInput.new()
	local c = game.ctx.pools.characters[1]
	game.camera.zoom = 2

	local function harvest(cycles)
		Fake.holdFor(game, input, "e", cycles * Config.harvest.handCycle + 0.05)
	end

	Fake.holdFor(game, input, "d", 1) -- flush against the east tree
	harvest(Config.nodes.tree.amount - 3)
	assertEqual(3, last.stage)

	Fake.holdFor(game, input, "a", 0.25) -- clear of the east tree and into the south tree's column
	Fake.holdFor(game, input, "s", 1)
	harvest(5)
	assertEqual(2, half.stage)
	assertEqual(Config.nodes.tree.amount - 3 + 5, Inventory.count(c.inventory, "log"))
	assertEqual(0, Inventory.count(c.inventory, "plank"), "the stockpile is in storage, not the inventory")
	Capture.capture("hud_last_stage_and_half_felled")
	assertEqual(1, rock.stage)
end)
