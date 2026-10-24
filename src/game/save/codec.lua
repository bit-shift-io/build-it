-- Turns a running session (ctx, src/game/session.lua) into the text of the
-- world save, and back into a session. Pure -- no `love.*`; reading and
-- writing the file is src/app/save_store.lua's job.
--
-- Line based, one record per line (src/game/save/records.lua: `tag
-- key=n:1 key=s:text ...`):
--
--   build-it-save 9
--   session seed=n:1 time=n:12.5 rng=n:<rng state> [nextNodeId=n:..] [nextAnimalId=n:..]
--   world width=n:128 height=n:128
--   character player=n:1 name=s:Ada x=n:.. y=n:.. facing=n:.. frame=n:.. health=n:..
--             hunger=n:.. tiredness=n:.. ...
--   inventory log=n:3 plank=n:50 ...      -- belongs to the character above
--   villager id=n:1 name=s:Bram x=n:.. y=n:.. facing=n:.. frame=n:.. distance=n:..
--   load item=s:log count=n:3             -- what the villager above carries,
--                                         -- only when it carries something
--   waypoint x=n:.. y=n:.. stud=b:true    -- the villager's path, next first; stud: a stud cell, not a tile
--   herd id=n:1 tileX=n:.. tileY=n:.. cap=n:4 breed=n:..   -- a deer herd
--   deer id=n:1 herd=n:1 x=n:.. y=n:.. facing=n:.. frame=n:.. distance=n:..
--                                         -- its path and wander timer are
--                                         -- not saved: it wanders anew
--   blueprint width=n:2 depth=n:1 storage=n:8
--                                         -- the k-th blueprint record is
--                                         -- blueprint k of the buildings
--                                         -- and sites below; equal
--                                         -- blueprints are saved once
--   ability ability=s:saw x=n:.. y=n:..   -- its roles, in order
--   portRole kind=s:input edge=s:S x=n:.. y=n:..
--   price plank=n:12                      -- its cost
--   traits productivity=n:.. capacity=n:.. reach=n:.. health=n:..
--   auras walkSpeed=n:.. harvestRate=n:..
--   walk width=n:12 depth=n:8 cells=s:..x.. -- its walk grid
--                                         -- (src/game/buildings/walk_grid.lua)
--   vertex x=n:.. y=n:.. z=n:.. nx=n:.. ny=n:.. nz=n:.. r=n:.. g=n:.. b=n:..
--          [material=s:.. slot=s:.. textureVariant=s:.. textureScale=n:.. textureRotation=n:..]
--                                         -- its mesh, one vertex a record
--   building id=n:2 design=s:mill blueprint=n:1 facing=s:N tileX=n:.. ...
--   storage log=n:3                       -- the building above's storage
--   port log=n:1                          -- each port's buffer, in order
--   function progress=n:.. state=s:..     -- each function brick, in order
--   site design=s:mill blueprint=n:1 facing=s:N tileX=n:.. tileY=n:.. progress=n:..
--   cost plank=n:30                       -- the site above's whole cost
--   delivered plank=n:12                  -- what haulers brought it
--   claim facility=n:1 store=n:0 item=s:plank count=n:18
--                                         -- its cost still claimed in a
--                                         -- storage facility: the facility's
--                                         -- place in the building records,
--                                         -- store 0 its storage, k its k-th
--                                         -- port buffer
--
-- A store's claimed counts (Storage.claim) are rebuilt from the sites'
-- claims; a site's builder is a job, so it is not saved either, but its
-- progress is.
--
-- Jobs (src/game/systems/job_system.lua) are not saved, nor the item and
-- room reservations they hold: after a load, free villagers take new jobs
-- from world state, and one carrying a load takes it to storage. So an
-- operator is dropped on load: its brick keeps its saved progress and
-- state but has no operator until a free villager takes the job anew, and
-- the next cycle starts from 0.
--
-- A building or site saves its whole blueprint (ADR 0007), so the world
-- loads and draws without the design library: a design deleted or edited
-- since leaves its buildings as they were. A blueprint's hash is its
-- content's (Blueprint.hash), so it is worked out again on load. A design
-- is kept by name only, a label.
--
-- Only state is saved; anything derived (indexes, traits, reach, sizes from
-- config) is rebuilt on load.
local Codec = require("src.game.save.records")
local Rng = require("src.core.rng")
local World = require("src.game.world")
local Session = require("src.game.session")
local Placement = require("src.game.buildings.placement")
local Site = require("src.game.buildings.site")
local Storage = require("src.game.components.storage")
local AnimalSystem = require("src.game.systems.animal_system")
local Blueprint = require("src.game.buildings.blueprint")

local SaveCodec = {}

-- Format 2 (villagers): placement pays from storage facilities and a new
-- game starts with one, so format 1 saves are refused, never migrated.
--
-- Format 3: a villager's experience follows its record as an `xp` record
-- (count per role). Format 2 saves load with empty experience.
--
-- Format 4: the player and each villager carry a `name`. Older saves give the
-- player a name from the new session's rng and a villager one from
-- config.names by its id.
--
-- Format 5: the player and each villager carry `health`, `hunger` and
-- `tiredness` (fractions 0..1) on their record. Older saves load with full
-- needs.
--
-- Format 6: a picked-clean berry bush carries `refilling` (seconds since it
-- ran out) on its node record. Older saves have no bushes, so load as is.
--
-- Format 7: `herd` and `deer` records for the animals pool. Older saves have
-- no deer, so load with none.
--
-- Format 8 (designs are Lua scripts, ADR 0006 and 0007): buildings and
-- sites carry blueprints, not design versions. Every older save is
-- refused, never migrated, so the fallbacks above no longer run.
--
-- Format 9 (ADR 0008): each blueprint carries its walk grid as a `walk`
-- record. It can't be rebuilt from a saved merged mesh, so format 8 saves
-- are refused.
local FORMAT = 9
local OLDEST = 9
local HEADER = "build-it-save " .. FORMAT

local function sessionRecord(ctx)
	return Codec.record("session", {
		seed = ctx.seed,
		time = ctx.time,
		rng = ctx.rng.state,
		nextNodeId = ctx.nextNodeId,
		nextAnimalId = ctx.nextAnimalId,
	})
end

local function characterRecords(lines, c)
	lines[#lines + 1] = Codec.record("character", {
		player = c.player,
		name = c.name,
		health = c.needs.health,
		hunger = c.needs.hunger,
		tiredness = c.needs.tiredness,
		x = c.x,
		y = c.y,
		facing = c.animator.facing,
		frame = c.animator.frame,
		distance = c.animator.distance,
		progress = c.harvester.progress,
		harvesting = c.harvester.node and c.harvester.node.id,
	})
	lines[#lines + 1] = Codec.record("inventory", c.inventory.counts)
end

local function villagerRecords(lines, v)
	lines[#lines + 1] = Codec.record("villager", {
		id = v.id,
		name = v.name,
		health = v.needs.health,
		hunger = v.needs.hunger,
		tiredness = v.needs.tiredness,
		x = v.x,
		y = v.y,
		facing = v.animator.facing,
		frame = v.animator.frame,
		distance = v.animator.distance,
	})
	if v.load.count > 0 then
		lines[#lines + 1] = Codec.record("load", { item = v.load.item, count = v.load.count })
	end
	if next(v.xp) then
		lines[#lines + 1] = Codec.record("xp", v.xp)
	end
	for _, p in ipairs(v.walker.path) do
		lines[#lines + 1] = Codec.record("waypoint", { x = p.x, y = p.y, stud = p.stud })
	end
end

-- The terrain, row by row, as runs of one terrain kind.
local function terrainRecords(lines, world)
	local kind, count = nil, 0
	local function flush()
		if count > 0 then
			lines[#lines + 1] = Codec.record("terrain", { kind = kind, count = count })
		end
	end
	for y = 0, world.height - 1 do
		for x = 0, world.width - 1 do
			local t = World.terrainAt(world, x, y)
			if t == kind then
				count = count + 1
			else
				flush()
				kind, count = t, 1
			end
		end
	end
	flush()
end

-- A mesh vertex as a flat record: its texture ({ variant, scale, rotation })
-- as textureVariant, textureScale and textureRotation.
local function vertexRecord(v)
	local t = v.texture
	if not t then
		return Codec.record("vertex", v)
	end
	local flat = {}
	for k, value in pairs(v) do
		flat[k] = value
	end
	flat.texture = nil
	flat.textureVariant, flat.textureScale, flat.textureRotation = t.variant, t.scale, t.rotation
	return Codec.record("vertex", flat)
end

-- A mesh vertex from its record's fields, its texture rebuilt.
local function vertexFrom(f)
	if f.textureVariant ~= nil then
		f.texture = { variant = f.textureVariant, scale = f.textureScale, rotation = f.textureRotation }
		f.textureVariant, f.textureScale, f.textureRotation = nil, nil, nil
	end
	return f
end

-- Every blueprint the buildings and sites in `placed` stand on, each once
-- (by content hash), in first-use order. Returns blueprint number by hash.
local function blueprintRecords(lines, placed)
	local numbers, count = {}, 0
	for _, b in ipairs(placed) do
		local bp = b.blueprint
		if not numbers[bp.hash] then
			count = count + 1
			numbers[bp.hash] = count
			lines[#lines + 1] = Codec.record("blueprint", { width = bp.width, depth = bp.depth, storage = bp.roles.storage })
			for _, a in ipairs(bp.roles.abilities) do
				lines[#lines + 1] = Codec.record("ability", a)
			end
			for _, p in ipairs(bp.roles.ports) do
				lines[#lines + 1] = Codec.record("portRole", p)
			end
			lines[#lines + 1] = Codec.record("price", bp.cost)
			lines[#lines + 1] = Codec.record("traits", bp.traits)
			lines[#lines + 1] = Codec.record("auras", bp.auras)
			lines[#lines + 1] = Codec.record("walk", bp.walk)
			for _, v in ipairs(bp.mesh) do
				lines[#lines + 1] = vertexRecord(v)
			end
		end
	end
	return numbers
end

-- A building's own state and its blueprint's number in `blueprints`; the
-- rest (footprint, ports, traits, sizes) is rebuilt from its blueprint on
-- load. A function brick's reserved node is saved as the node's id.
local function buildingRecords(lines, b, blueprints)
	lines[#lines + 1] = Codec.record("building", {
		id = b.id,
		design = b.design,
		blueprint = blueprints[b.blueprint.hash],
		facing = b.facing,
		tileX = b.tileX,
		tileY = b.tileY,
		full = b.full,
	})
	lines[#lines + 1] = Codec.record("storage", b.storage.counts)
	for _, port in ipairs(b.ports) do
		lines[#lines + 1] = Codec.record("port", port.buffer.counts)
	end
	for _, fb in ipairs(b.functionBricks) do
		lines[#lines + 1] = Codec.record("function", {
			progress = fb.progress,
			state = fb.state,
			node = fb.node and fb.node.id,
		})
	end
end

-- A construction site's own state and its blueprint's number in
-- `blueprints`; its footprint is rebuilt from its blueprint on load.
local function siteRecords(lines, site, ctx, blueprints)
	lines[#lines + 1] = Codec.record("site", {
		design = site.design,
		blueprint = blueprints[site.blueprint.hash],
		facing = site.facing,
		tileX = site.tileX,
		tileY = site.tileY,
		progress = site.progress,
	})
	lines[#lines + 1] = Codec.record("cost", site.cost)
	lines[#lines + 1] = Codec.record("delivered", site.delivered.counts)
	local place = {}
	for i, b in ipairs(ctx.pools.buildings) do
		place[b] = i
	end
	for _, claim in ipairs(site.claims) do
		local b, store = claim.building, 0
		for k, port in ipairs(b.ports) do
			if port.buffer == claim.store then
				store = k
			end
		end
		lines[#lines + 1] = Codec.record("claim", { facility = place[b], store = store, item = claim.item, count = claim.count })
	end
end

-- The save text of session `ctx`.
function SaveCodec.encode(ctx)
	local lines = { HEADER, sessionRecord(ctx) }
	lines[#lines + 1] = Codec.record("world", { width = ctx.world.width, height = ctx.world.height })
	terrainRecords(lines, ctx.world)
	for _, n in ipairs(ctx.pools.nodes) do
		lines[#lines + 1] = Codec.record("node", n, "reservedBy")
	end
	local placed = {}
	for _, list in ipairs({ ctx.pools.buildings, ctx.pools.sites }) do
		for _, b in ipairs(list) do
			placed[#placed + 1] = b
		end
	end
	local blueprints = blueprintRecords(lines, placed)
	for _, b in ipairs(ctx.pools.buildings) do
		buildingRecords(lines, b, blueprints)
	end
	for _, site in ipairs(ctx.pools.sites) do
		siteRecords(lines, site, ctx, blueprints)
	end
	for _, c in ipairs(ctx.pools.characters) do
		characterRecords(lines, c)
	end
	for _, v in ipairs(ctx.pools.villagers) do
		villagerRecords(lines, v)
	end
	for _, h in ipairs(ctx.pools.herds) do
		lines[#lines + 1] = Codec.record("herd", { id = h.id, tileX = h.tileX, tileY = h.tileY, cap = h.cap, breed = h.breed })
	end
	for _, a in ipairs(ctx.pools.animals) do
		lines[#lines + 1] = Codec.record("deer", {
			id = a.id,
			herd = a.herd,
			x = a.x,
			y = a.y,
			facing = a.animator.facing,
			frame = a.animator.frame,
			distance = a.animator.distance,
		})
	end
	return table.concat(lines, "\n") .. "\n"
end

-- Every record of `text` as { tag, fields }, or nil and why.
local function parse(text)
	if type(text) ~= "string" then
		return nil, "no text"
	end
	local records = {}
	local n = 0
	for line in text:gmatch("[^\n]+") do
		n = n + 1
		if n == 1 then
			local format = tonumber(line:match("^build%-it%-save (%d+)$"))
			if not (format and format >= OLDEST and format <= FORMAT) then
				if format and format < OLDEST then
					return nil, "save is from an older version of the game (format " .. format .. ")"
				end
				return nil, "not a world save"
			end
		else
			local tag, fields = Codec.parse(line, n)
			if not tag then
				return nil, fields
			end
			records[#records + 1] = { tag = tag, fields = fields, line = n }
		end
	end
	if n == 0 then
		return nil, "empty save"
	end
	return records
end

-- Puts saved needs back; fields an older save lacks keep their defaults.
local function restoreNeeds(r, f)
	r.needs.health = f.health or r.needs.health
	r.needs.hunger = f.hunger or r.needs.hunger
	r.needs.tiredness = f.tiredness or r.needs.tiredness
end

local function restoreCharacter(c, f, nodesById)
	restoreNeeds(c, f)
	c.x, c.y = f.x, f.y
	c.name = f.name or c.name
	c.animator.facing, c.animator.frame, c.animator.distance = f.facing, f.frame, f.distance
	c.harvester.progress = f.progress
	c.harvester.node = f.harvesting and nodesById[f.harvesting]
end

local function copy(t)
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	return out
end

-- The placement request of a saved building or site `f`, its blueprint
-- from `blueprints`; raises when the save holds no such blueprint.
local function request(f, blueprints, what)
	local blueprint = blueprints[f.blueprint]
	if not blueprint then
		error(what .. " has no saved blueprint")
	end
	return { design = f.design, blueprint = blueprint, facing = f.facing, tileX = f.tileX, tileY = f.tileY }
end

-- Rebuilds building `saved` = { fields, storage, ports, functions } from its
-- blueprint through Placement.assemble, then puts back its own state.
local function restoreBuilding(ctx, saved, blueprints, nodesById)
	local f = saved.fields
	local what = "building " .. tostring(f.id)
	local b = Placement.assemble(f.id, request(f, blueprints, what), ctx.config)
	if #saved.ports ~= #b.ports or #saved.functions ~= #b.functionBricks then
		error(what .. " does not match its blueprint")
	end
	b.full = f.full
	b.storage.counts = copy(saved.storage)
	for i, port in ipairs(b.ports) do
		port.buffer.counts = copy(saved.ports[i])
	end
	for i, fb in ipairs(b.functionBricks) do
		local sf = saved.functions[i]
		fb.progress, fb.state = sf.progress, sf.state
		if sf.node then
			local node = assert(nodesById[sf.node], "reserved node " .. sf.node .. " is missing")
			node.reservedBy = fb
			fb.node = node
		end
	end
	table.insert(ctx.pools.buildings, b)
	World.addBuilding(ctx.world, b)
end

-- Rebuilds site `saved` = { fields, cost, delivered, claims } from its
-- blueprint, claiming its claims again in the facilities' stores.
local function restoreSite(ctx, saved, blueprints)
	local f = saved.fields
	local req = request(f, blueprints, "a site")
	local claims = {}
	for _, c in ipairs(saved.claims) do
		local b = assert(ctx.pools.buildings[c.facility], "a site claims from a missing facility")
		local store = c.store == 0 and b.storage or assert(b.ports[c.store], "a site claims from a missing port").buffer
		Storage.claim(store, c.item, c.count)
		claims[#claims + 1] = { building = b, store = store, item = c.item, count = c.count, taking = 0 }
	end
	local width, depth = Placement.footprint(req.blueprint, f.facing)
	local site = Site.new(req, req.blueprint, width, depth, copy(saved.cost), claims)
	site.delivered.counts = copy(saved.delivered)
	site.progress = f.progress
	table.insert(ctx.pools.sites, site)
	World.addBuilding(ctx.world, site)
end

-- The session from parsed records; raises on anything inconsistent.
local function build(records, config)
	local session, world
	local characters, buildings, villagers, sites = {}, {}, {}, {}
	local herds, animals = {}, {}
	local blueprints = {}
	local nodesById = {}
	local tile = 0 -- terrain tiles read so far
	local function last(list, what, line)
		return list[#list] or error("line " .. line .. " is a " .. what .. " outside its owner")
	end
	for _, r in ipairs(records) do
		local f, tag = r.fields, r.tag
		if tag == "session" then
			session = f
		elseif tag == "world" then
			world = World.new(f.width, f.height)
		elseif tag == "terrain" then
			assert(world and tile + f.count <= #world.terrain, "line " .. r.line .. " runs past the world's tiles")
			for i = tile + 1, tile + f.count do
				world.terrain[i] = f.kind
			end
			tile = tile + f.count
		elseif tag == "node" then
			assert(world, "line " .. r.line .. " is a node before the world")
			World.addNode(world, f)
			nodesById[f.id] = f
		elseif tag == "blueprint" then
			blueprints[#blueprints + 1] = {
				width = f.width,
				depth = f.depth,
				mesh = {},
				roles = { abilities = {}, ports = {}, storage = f.storage },
				cost = {},
				traits = {},
				auras = {},
			}
		elseif tag == "ability" then
			table.insert(last(blueprints, tag, r.line).roles.abilities, f)
		elseif tag == "portRole" then
			table.insert(last(blueprints, tag, r.line).roles.ports, f)
		elseif tag == "price" then
			last(blueprints, tag, r.line).cost = f
		elseif tag == "traits" or tag == "auras" or tag == "walk" then
			last(blueprints, tag, r.line)[tag] = f
		elseif tag == "vertex" then
			table.insert(last(blueprints, tag, r.line).mesh, vertexFrom(f))
		elseif tag == "building" then
			buildings[#buildings + 1] = { fields = f, storage = {}, ports = {}, functions = {} }
		elseif tag == "storage" then
			last(buildings, tag, r.line).storage = f
		elseif tag == "port" then
			table.insert(last(buildings, tag, r.line).ports, f)
		elseif tag == "function" then
			table.insert(last(buildings, tag, r.line).functions, f)
		elseif tag == "site" then
			sites[#sites + 1] = { fields = f, cost = {}, delivered = {}, claims = {} }
		elseif tag == "cost" or tag == "delivered" then
			last(sites, tag, r.line)[tag] = f
		elseif tag == "claim" then
			table.insert(last(sites, tag, r.line).claims, f)
		elseif tag == "character" then
			characters[#characters + 1] = { fields = f, inventory = {} }
		elseif tag == "inventory" then
			last(characters, tag, r.line).inventory = f
		elseif tag == "villager" then
			local v = Session.newVillager(f.id, f.x, f.y, config)
			v.animator.facing, v.animator.frame, v.animator.distance = f.facing, f.frame, f.distance
			v.name = f.name or config.names[(f.id - 1) % #config.names + 1]
			restoreNeeds(v, f)
			villagers[#villagers + 1] = v
		elseif tag == "herd" then
			herds[#herds + 1] = { id = f.id, tileX = f.tileX, tileY = f.tileY, cap = f.cap, breed = f.breed or 0 }
		elseif tag == "deer" then
			local a = AnimalSystem.newDeer(f.id, f.herd, f.x, f.y, config)
			a.animator.facing, a.animator.frame, a.animator.distance = f.facing, f.frame, f.distance
			animals[#animals + 1] = a
		elseif tag == "load" then
			local load = last(villagers, tag, r.line).load
			load.item, load.count = f.item, f.count
		elseif tag == "xp" then
			last(villagers, tag, r.line).xp = f
		elseif tag == "waypoint" then
			table.insert(last(villagers, tag, r.line).walker.path, { x = f.x, y = f.y, stud = f.stud })
		else
			error("line " .. r.line .. " has an unknown record " .. tag)
		end
	end
	assert(session and world, "no session or world record")
	for _, bp in ipairs(blueprints) do
		bp.hash = Blueprint.hash(bp)
	end

	local ctx = Session.new(world, config, session.seed)
	ctx.time = session.time
	ctx.rng = Rng.new(0)
	ctx.rng.state = session.rng
	ctx.nextNodeId = session.nextNodeId
	ctx.nextAnimalId = session.nextAnimalId
	for i, saved in ipairs(characters) do
		local c = assert(ctx.pools.characters[i], "more characters than the session holds")
		restoreCharacter(c, saved.fields, nodesById)
		c.inventory.counts = saved.inventory
	end
	for _, saved in ipairs(buildings) do
		restoreBuilding(ctx, saved, blueprints, nodesById)
	end
	for _, saved in ipairs(sites) do
		restoreSite(ctx, saved, blueprints)
	end
	ctx.pools.villagers = villagers
	for i, h in ipairs(herds) do
		assert(h.id == i, "herds are out of order")
	end
	for _, a in ipairs(animals) do
		assert(herds[a.herd], "a deer belongs to a missing herd")
	end
	ctx.pools.herds, ctx.pools.animals = herds, animals
	return ctx
end

-- A session from save text `text`, with tuning from `config`; or nil and
-- why it could not be read.
function SaveCodec.decode(text, config)
	local records, reason = parse(text)
	if not records then
		return nil, reason
	end
	local ok, result = pcall(build, records, config)
	if not ok then
		return nil, tostring(result)
	end
	return result
end

return SaveCodec
