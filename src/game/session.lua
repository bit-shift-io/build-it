-- A running game session: builds ctx and owns the single frame-order
-- function, Session.step (docs/ARCHITECTURE.md "Systems and frame order").
-- Pure -- no `love.*`; runs under plain LuaJIT.
local Rng = require("src.core.rng")
local World = require("src.game.world")
local CharacterSystem = require("src.game.systems.character_system")
local NodeSystem = require("src.game.systems.node_system")
local Inventory = require("src.game.components.inventory")

local Session = {}

local function newCharacter(id, player, x, y, config)
	return {
		id = id,
		player = player,
		x = x,
		y = y,
		size = config.character.size,
		mover = { speed = config.character.speed },
		inventory = Inventory.new(config.stockpile),
		harvester = { progress = 0 },
	}
end

-- world: a world table (src/game/world.lua), literal or from
-- src/game/world_gen.lua. seed fixes ctx.rng. The world's node pool is
-- ctx.pools.nodes (the same table).
function Session.new(world, config, seed)
	local ctx = {
		dt = 0,
		time = 0,
		world = world,
		config = config,
		seed = seed,
		rng = Rng.new(seed),
		intents = {},
		pools = { characters = {}, nodes = world.nodes or {} },
	}
	local cx, cy = World.center(world, config)
	table.insert(ctx.pools.characters, newCharacter(1, 1, cx, cy, config))
	return ctx
end

-- The whole frame order, in one place. ctx.dt must already be set.
--   1. Intents: `app` (or a test) fills ctx.intents[player] before the step.
--   2. Characters: walk, then hand-harvest.
--   3. Despawn sweep (last): depleted nodes leave the pool. Nothing is ever
--      removed mid-iteration.
function Session.step(ctx)
	CharacterSystem.update(ctx)
	NodeSystem.despawn(ctx)
end

-- One fixed step: `app` accumulates real time and calls this every 1/60 s.
function Session.advance(ctx, dt)
	ctx.dt = dt
	ctx.time = ctx.time + dt
	Session.step(ctx)
end

return Session
