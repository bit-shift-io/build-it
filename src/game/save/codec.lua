-- Turns a running session (ctx, src/game/session.lua) into the text of the
-- world save, and back into a session. Pure -- no `love.*`; reading and
-- writing the file is src/app/save_store.lua's job.
--
-- Line based like a design file, with the same record format
-- (src/game/designs/codec.lua: `tag key=n:1 key=s:text ...`):
--
--   build-it-save 2
--   session seed=n:1 time=n:12.5 rng=n:<rng state> [nextNodeId=n:..]
--   world width=n:128 height=n:128
--   character player=n:1 x=n:.. y=n:.. facing=n:.. frame=n:.. ...
--   inventory log=n:3 plank=n:50 ...      -- belongs to the character above
--   villager id=n:1 x=n:.. y=n:.. facing=n:.. frame=n:.. distance=n:..
--   load item=s:log count=n:3             -- what the villager above carries,
--                                         -- only when it carries something
--   waypoint x=n:.. y=n:..                -- the villager's path, next first
--   site design=s:d1 version=n:1 facing=s:N tileX=n:.. tileY=n:.. progress=n:..
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
-- Only state is saved; anything derived (indexes, traits, reach, sizes from
-- config) is rebuilt on load.
local Codec = require("src.game.designs.codec")
local Rng = require("src.core.rng")
local World = require("src.game.world")
local Session = require("src.game.session")
local Placement = require("src.game.buildings.placement")
local Site = require("src.game.buildings.site")
local Storage = require("src.game.components.storage")

local SaveCodec = {}

-- Format 2 (villagers): placement pays from storage facilities and a new
-- game starts with one, so format 1 saves are refused, never migrated.
local FORMAT = 2
local HEADER = "build-it-save " .. FORMAT

local function sessionRecord(ctx)
	return Codec.record("session", {
		seed = ctx.seed,
		time = ctx.time,
		rng = ctx.rng.state,
		nextNodeId = ctx.nextNodeId,
	})
end

local function characterRecords(lines, c)
	lines[#lines + 1] = Codec.record("character", {
		player = c.player,
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
		x = v.x,
		y = v.y,
		facing = v.animator.facing,
		frame = v.animator.frame,
		distance = v.animator.distance,
	})
	if v.load.count > 0 then
		lines[#lines + 1] = Codec.record("load", { item = v.load.item, count = v.load.count })
	end
	for _, p in ipairs(v.walker.path) do
		lines[#lines + 1] = Codec.record("waypoint", { x = p.x, y = p.y })
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

-- A snapshot of every design version a building stands on, so the world
-- loads and draws without the design library: per design, its record and
-- each referenced version (numbered `n`) with its bricks. The built-in
-- starter design (src/game/designs/starter.lua) is snapshotted like any
-- other, under its reserved id.
local function snapshotRecords(lines, buildings)
	local designs, order = {}, {}
	for _, b in ipairs(buildings) do
		local id = b.design.id
		if not designs[id] then
			designs[id] = { design = b.design, versions = {} }
			order[#order + 1] = id
		end
		designs[id].versions[b.version] = true
	end
	for _, id in ipairs(order) do
		local entry = designs[id]
		lines[#lines + 1] = Codec.record("design", { id = id, name = entry.design.name })
		local numbers = {}
		for n in pairs(entry.versions) do
			numbers[#numbers + 1] = n
		end
		table.sort(numbers)
		for _, n in ipairs(numbers) do
			local version = entry.design.versions[n]
			local fields = { n = n }
			for k, v in pairs(version) do
				if k ~= "bricks" then
					fields[k] = v
				end
			end
			lines[#lines + 1] = Codec.record("version", fields)
			for _, brick in ipairs(version.bricks) do
				lines[#lines + 1] = Codec.record("brick", brick)
			end
		end
	end
end

-- A building's own state; the rest (footprint, ports, traits, sizes) is
-- rebuilt from its design version on load. A function brick's reserved
-- node is saved as the node's id.
local function buildingRecords(lines, b)
	lines[#lines + 1] = Codec.record("building", {
		id = b.id,
		design = b.design.id,
		version = b.version,
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

-- A construction site's own state; its footprint is rebuilt from its
-- design version on load.
local function siteRecords(lines, site, ctx)
	lines[#lines + 1] = Codec.record("site", {
		design = site.design.id,
		version = site.version,
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
	snapshotRecords(lines, placed)
	for _, b in ipairs(ctx.pools.buildings) do
		buildingRecords(lines, b)
	end
	for _, site in ipairs(ctx.pools.sites) do
		siteRecords(lines, site, ctx)
	end
	for _, c in ipairs(ctx.pools.characters) do
		characterRecords(lines, c)
	end
	for _, v in ipairs(ctx.pools.villagers) do
		villagerRecords(lines, v)
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
			if line ~= HEADER then
				local format = tonumber(line:match("^build%-it%-save (%d+)$"))
				if format and format < FORMAT then
					return nil, "save is from an older version of the game (format " .. format .. ")"
				end
				return nil, "not a world save"
			end
		else
			local tag, fields = Codec.parseRecord(line, n)
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

local function restoreCharacter(c, f, nodesById)
	c.x, c.y = f.x, f.y
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

-- Rebuilds building `saved` = { fields, storage, ports, functions } from its
-- design version through Placement.assemble, then puts back its own state.
local function restoreBuilding(ctx, saved, designs, nodesById)
	local f = saved.fields
	local design = designs[f.design]
	if not (design and design.versions[f.version]) then
		error("building " .. tostring(f.id) .. " has no snapshot of its design version")
	end
	local request = { design = design, version = f.version, facing = f.facing, tileX = f.tileX, tileY = f.tileY }
	local b = Placement.assemble(f.id, request, ctx.config)
	if #saved.ports ~= #b.ports or #saved.functions ~= #b.functionBricks then
		error("building " .. tostring(f.id) .. " does not match its design version")
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
-- design version, claiming its claims again in the facilities' stores.
local function restoreSite(ctx, saved, designs)
	local f = saved.fields
	local design = designs[f.design]
	local version = design and design.versions[f.version]
	if not version then
		error("a site has no snapshot of its design version")
	end
	local request = { design = design, version = f.version, facing = f.facing, tileX = f.tileX, tileY = f.tileY }
	local claims = {}
	for _, c in ipairs(saved.claims) do
		local b = assert(ctx.pools.buildings[c.facility], "a site claims from a missing facility")
		local store = c.store == 0 and b.storage or assert(b.ports[c.store], "a site claims from a missing port").buffer
		Storage.claim(store, c.item, c.count)
		claims[#claims + 1] = { building = b, store = store, item = c.item, count = c.count, taking = 0 }
	end
	local width, depth = Placement.footprint(version, f.facing)
	local site = Site.new(request, width, depth, copy(saved.cost), claims)
	site.delivered.counts = copy(saved.delivered)
	site.progress = f.progress
	table.insert(ctx.pools.sites, site)
	World.addBuilding(ctx.world, site)
end

-- The session from parsed records; raises on anything inconsistent.
local function build(records, config)
	local session, world
	local characters, buildings, villagers, sites = {}, {}, {}, {}
	local designs, design, version = {}, nil, nil
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
		elseif tag == "design" then
			design = { id = f.id, name = f.name, versions = {} }
			designs[f.id] = design
			version = nil
		elseif tag == "version" then
			assert(design, "line " .. r.line .. " is a version outside any design")
			version = f
			design.versions[f.n] = version
			version.n = nil
			version.bricks = {}
		elseif tag == "brick" then
			table.insert(assert(version, "line " .. r.line .. " is a brick outside any version").bricks, f)
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
			villagers[#villagers + 1] = v
		elseif tag == "load" then
			local load = last(villagers, tag, r.line).load
			load.item, load.count = f.item, f.count
		elseif tag == "waypoint" then
			table.insert(last(villagers, tag, r.line).walker.path, { x = f.x, y = f.y })
		else
			error("line " .. r.line .. " has an unknown record " .. tag)
		end
	end
	assert(session and world, "no session or world record")

	local ctx = Session.new(world, config, session.seed)
	ctx.time = session.time
	ctx.rng = Rng.new(0)
	ctx.rng.state = session.rng
	ctx.nextNodeId = session.nextNodeId
	for i, saved in ipairs(characters) do
		local c = assert(ctx.pools.characters[i], "more characters than the session holds")
		restoreCharacter(c, saved.fields, nodesById)
		c.inventory.counts = saved.inventory
	end
	for _, saved in ipairs(buildings) do
		restoreBuilding(ctx, saved, designs, nodesById)
	end
	for _, saved in ipairs(sites) do
		restoreSite(ctx, saved, designs)
	end
	ctx.pools.villagers = villagers
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
