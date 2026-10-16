-- Turns a running session (ctx, src/game/session.lua) into the text of the
-- world save, and back into a session. Pure -- no `love.*`; reading and
-- writing the file is src/app/save_store.lua's job.
--
-- Line based like a design file, with the same record format
-- (src/game/designs/codec.lua: `tag key=n:1 key=s:text ...`):
--
--   build-it-save 1
--   session seed=n:1 time=n:12.5 rng=n:<rng state> [nextNodeId=n:..]
--   world width=n:128 height=n:128
--   character player=n:1 x=n:.. y=n:.. facing=n:.. frame=n:.. ...
--   inventory log=n:3 plank=n:50 ...      -- belongs to the character above
--
-- Only state is saved; anything derived (indexes, traits, reach, sizes from
-- config) is rebuilt on load.
local Codec = require("src.game.designs.codec")
local Rng = require("src.core.rng")
local World = require("src.game.world")
local Session = require("src.game.session")
local Building = require("src.game.buildings.building")
local Placement = require("src.game.buildings.placement")

local SaveCodec = {}

local HEADER = "build-it-save 1"

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
-- each referenced version (numbered `n`) with its bricks.
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
			converting = fb.converting,
			node = fb.node and fb.node.id,
		})
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
	snapshotRecords(lines, ctx.pools.buildings)
	for _, b in ipairs(ctx.pools.buildings) do
		buildingRecords(lines, b)
	end
	for _, c in ipairs(ctx.pools.characters) do
		characterRecords(lines, c)
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
-- design version through Building.new, then puts back its own state.
local function restoreBuilding(ctx, saved, designs, nodesById)
	local f = saved.fields
	local design = designs[f.design]
	if not (design and design.versions[f.version]) then
		error("building " .. tostring(f.id) .. " has no snapshot of its design version")
	end
	local version = design.versions[f.version]
	local request = { design = design, version = f.version, facing = f.facing, tileX = f.tileX, tileY = f.tileY }
	local width, depth = Placement.footprint(version, f.facing)
	local ports = Placement.ports(version, f.facing, f.tileX, f.tileY, ctx.config.builder)
	local b = Building.new(f.id, request, width, depth, ports, ctx.config)
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
		fb.progress, fb.state, fb.converting = sf.progress, sf.state, sf.converting
		if sf.node then
			local node = assert(nodesById[sf.node], "reserved node " .. sf.node .. " is missing")
			node.reservedBy = fb
			fb.node = node
		end
	end
	table.insert(ctx.pools.buildings, b)
	World.addBuilding(ctx.world, b)
end

-- The session from parsed records; raises on anything inconsistent.
local function build(records, config)
	local session, world
	local characters, buildings = {}, {}
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
		elseif tag == "character" then
			characters[#characters + 1] = { fields = f, inventory = {} }
		elseif tag == "inventory" then
			last(characters, tag, r.line).inventory = f
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
