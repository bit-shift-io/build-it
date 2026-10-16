-- Pool system for ctx.pools.buildings and ctx.pools.sites: places the
-- construction sites players ask for (intent.place,
-- src/game/buildings/placement.lua), turns every built site into a
-- building, then runs every building's function bricks and moves its
-- stored products to its outputs.
local Placement = require("src.game.buildings.placement")
local Site = require("src.game.buildings.site")
local FunctionBrick = require("src.game.components.function_brick")
local Ports = require("src.game.components.ports")
local NodeSystem = require("src.game.systems.node_system")
local World = require("src.game.world")

local BuildingSystem = {}

function BuildingSystem.update(ctx)
	for _, c in ipairs(ctx.pools.characters) do
		local intent = ctx.intents[c.player]
		if intent and intent.place then
			Placement.place(ctx, intent.place)
		end
	end
	for _, site in ipairs(ctx.pools.sites) do
		if not site.dead and Site.built(site, ctx.config) then
			Placement.build(ctx, Site.request(site))
			site.dead = true
		end
	end
	for _, b in ipairs(ctx.pools.buildings) do
		for _, fb in ipairs(b.functionBricks) do
			FunctionBrick.update(fb, b, ctx)
		end
		Ports.flush(b)
		b.full = not Ports.hasRoom(b)
	end
end

-- Despawn sweep for buildings marked `dead`: their function bricks release
-- their nodes and their tiles clear. The only place buildings leave the
-- pool.
function BuildingSystem.despawn(ctx)
	local pool = ctx.pools.buildings
	for i = #pool, 1, -1 do
		local b = pool[i]
		if b.dead then
			for _, fb in ipairs(b.functionBricks) do
				if fb.node then
					NodeSystem.release(fb.node)
				end
			end
			World.removeBuilding(ctx.world, b)
			table.remove(pool, i)
		end
	end
	-- Built sites: their building already holds their tiles.
	local sites = ctx.pools.sites
	for i = #sites, 1, -1 do
		if sites[i].dead then
			World.removeBuilding(ctx.world, sites[i])
			table.remove(sites, i)
		end
	end
end

return BuildingSystem
