-- The builder screen (docs/CONTEXT.md "Builder"): a live 3D view of the
-- draft on the right, a sidebar on the left. Left-click places a brick on
-- the surface under the cursor; shift-left-click paints the brick under it;
-- right-click removes the brick under it; right-drag orbits; the wheel
-- zooms. R turns the held brick. Ctrl+Z undoes and Ctrl+Shift+Z redoes
-- every draft change. Sidebar buttons resize the baseplate and pick the
-- held brick's shape (plain, function, port or storage brick), material
-- and paint. The info panel on the right shows the draft's traits, its cost
-- against what storage holds (red where short) and every design rule
-- it breaks (src/game/builder/validate.lua); save is refused while it
-- breaks one.
--
-- The Design section names the draft (click Name, type, Enter), saves it to
-- the design library (src/app/design_store.lua) as a new version of the
-- design it was opened from, or as a new design; New starts an empty draft;
-- Open lists the library's designs with a live version in place of the
-- brick pickers. A click expands a design into its live versions, newest
-- first, each with Open (edit that version) and Delete. Delete arms on the
-- first click and deletes on a second click on the same row; any other
-- click disarms it. A delete writes the design file and never touches the
-- draft on screen.
--
-- Picking runs through src/game/builder/pick.lua with the ray from the same
-- camera view the screen draws with.
local Draft = require("src.game.builder.draft")
local Pick = require("src.game.builder.pick")
local History = require("src.game.builder.history")
local Library = require("src.game.designs.library")
local Cost = require("src.game.builder.cost")
local Traits = require("src.game.builder.traits")
local Validate = require("src.game.builder.validate")
local DesignStore = require("src.app.design_store")
local BuilderCamera = require("src.app.builder_camera")
local BuilderView = require("src.app.render.builder_view")
local Screen = require("src.app.screen")

local BuilderScreen = {}

-- Sidebar layout, in pixels from the window's top-left.
local PAD = 16
local BUTTON_HEIGHT = 32
local BUTTONS_TOP = 72
local GAP = 8
-- Room under the resize rows for the refusal message.
local MESSAGE_HEIGHT = 40
-- Room above each picker section for its heading.
local HEADING_HEIGHT = 20
local SHAPE_COLUMNS, SHAPE_HEIGHT = 3, 28
local SWATCH_COLUMNS, SWATCH_HEIGHT = 6, 24
local DESIGN_ROW_HEIGHT = 28
local DESIGN_LIST_HEIGHT = 24

-- The label a design saved without a name gets.
local DEFAULT_NAME = "Untitled"

-- Shown when a resize is refused, keyed by Draft.resize's reason.
local REFUSALS = {
	size = "The baseplate is 1 to 4 tiles a side.",
	bricks = "Bricks sit outside that size.",
}

-- What each design rule a draft breaks says (src/game/builder/validate.lua),
-- in the info panel and when a save is refused, keyed by the rule's reason.
BuilderScreen.PROBLEMS = {
	["no function brick"] = "Add a saw, pickaxe, planter or saw bench.",
	["no output port"] = "Add an output port.",
	["port off edge"] = "Ports go on the baseplate's edge, at ground level.",
	["saw bench without input"] = "A saw bench needs an input port.",
}

-- Shown when a save is refused, keyed by Library.canSave's reason.
local SAVE_REFUSALS = setmetatable({
	empty = "Place a brick before saving.",
}, { __index = BuilderScreen.PROBLEMS })

local function problemsMessage(problems)
	if #problems == 0 then
		return nil
	end
	return #problems == 1 and "1 design file could not be read." or #problems .. " design files could not be read."
end

-- library: the design library (read once per launch by src/app/flow.lua);
-- problems lists its files that could not be read ({ name, reason });
-- stock() returns what the storage facilities hold ({ [item] = n },
-- src/game/components/storage_facility.lua), read live to show what the
-- draft's cost is short of. The builder never spends it.
function BuilderScreen.new(config, library, problems, stock)
	local cfg = config.builder
	return {
		config = config,
		cfg = cfg,
		library = library,
		problems = problems,
		stock = stock,
		draft = Draft.new(),
		-- The design the draft was opened from or last saved as (nil for a
		-- new one), and its name as typed.
		designId = nil,
		name = "",
		-- Whether typed text goes to the name.
		typingName = false,
		-- Whether the sidebar lists the library instead of the brick pickers.
		browsing = false,
		-- The design id the Open list shows version rows for, or nil.
		expanded = nil,
		-- The Delete awaiting its confirming click: { id, n }, or nil.
		armed = nil,
		-- Undo/redo for every draft change (src/game/builder/history.lua).
		history = History.new(),
		-- The brick in hand: { shape, rotation, material, paint }.
		held = { shape = cfg.held.shape, rotation = cfg.held.rotation, material = cfg.held.material, paint = cfg.held.paint },
		camera = BuilderCamera.new(cfg),
		-- Bumped on every draft change, so the view remeshes only then.
		revision = 0,
		mouseX = nil,
		mouseY = nil,
		-- The right button's press, until release: { x, y, moved }.
		rightPress = nil,
		-- Why the last resize or save was refused, what a save did, or which
		-- design files could not be read.
		message = problemsMessage(problems),
	}
end

-- The 3D view's rectangle: the window between the sidebar and the info
-- panel.
function BuilderScreen.viewport(screen)
	local w, h = Screen.dimensions()
	local side = screen.cfg.sidebarWidth
	return { x = side, y = 0, width = w - side - screen.cfg.infoWidth, height = h }
end

-- The info panel's rectangle, at the window's right edge.
function BuilderScreen.infoPanel(screen)
	local w, h = Screen.dimensions()
	local width = screen.cfg.infoWidth
	return { x = w - width, y = 0, width = width, height = h }
end

-- What the info panel shows for the draft, live:
--   traits   = { productivity, capacity, reach, health } (Traits.of)
--   cost     = { { item, need, have, short }, ... } by item name; short
--              when storage holds less than the draft needs
--   problems = the text of each design rule it breaks, in rule order
function BuilderScreen.info(screen)
	local cost = {}
	local stock = screen.stock()
	for item, need in pairs(Cost.of(screen.draft, screen.config)) do
		local have = stock[item] or 0
		table.insert(cost, { item = item, need = need, have = have, short = have < need })
	end
	table.sort(cost, function(a, b)
		return a.item < b.item
	end)
	local problems = {}
	for i, reason in ipairs(Validate.problems(screen.draft, screen.cfg)) do
		problems[i] = BuilderScreen.PROBLEMS[reason]
	end
	return { traits = Traits.of(screen.draft, screen.config), auras = Traits.auras(screen.draft, screen.config), cost = cost, problems = problems }
end

-- This frame's camera view (src/app/builder_camera.lua).
function BuilderScreen.view(screen)
	return BuilderCamera.view(screen.camera, screen.draft, screen.cfg, BuilderScreen.viewport(screen))
end

local function capitalised(s)
	return s:sub(1, 1):upper() .. s:sub(2)
end

-- Lays `items` ({ label, value }) out in a grid of `columns` from `top`,
-- appending one `kind` button per item to `out`. Returns the y below it.
local function grid(out, screen, kind, items, columns, height, top)
	local width = (screen.cfg.sidebarWidth - 2 * PAD - (columns - 1) * GAP) / columns
	for i, item in ipairs(items) do
		local col, row = (i - 1) % columns, math.floor((i - 1) / columns)
		table.insert(out, {
			kind = item.kind or kind,
			label = item.label,
			value = item.value,
			version = item.version,
			armed = item.armed,
			x = PAD + col * (width + GAP),
			y = top + row * (height + GAP),
			width = width,
			height = height,
		})
	end
	return top + math.ceil(#items / columns) * (height + GAP)
end

-- The sidebar's buttons, each { kind, label, x, y, width, height, ... }:
--   kind "resize": dw/dd, the change to the baseplate's width/depth in tiles
--   kind "name": the name field; "save", "new", "open": the design actions
--   kind "shape" | "material" | "paint": value, what it sets on the held
--     brick (a cfg.bricks name, a cfg.materials name, a cfg.palette index;
--     swatches are labelled "paint:<index>")
--   kind "expand": value, a live library design's id, while browsing
--     replaces the pickers; "openVersion" | "deleteVersion": value, the
--     expanded design's id, version, its number, armed, whether this
--     Delete awaits its confirming click
-- The first button of each section after the resize rows has `heading`,
-- its section title.
function BuilderScreen.buttons(screen)
	local cfg = screen.cfg
	local half = (cfg.sidebarWidth - 3 * PAD) / 2
	local rows = {
		{ "Width -", "Width +", dw = 1, dd = 0 },
		{ "Depth -", "Depth +", dw = 0, dd = 1 },
	}
	local out = {}
	local y = BUTTONS_TOP
	for _, row in ipairs(rows) do
		table.insert(out, { kind = "resize", label = row[1], x = PAD, y = y, width = half, height = BUTTON_HEIGHT, dw = -row.dw, dd = -row.dd })
		table.insert(out, { kind = "resize", label = row[2], x = 2 * PAD + half, y = y, width = half, height = BUTTON_HEIGHT, dw = row.dw, dd = row.dd })
		y = y + BUTTON_HEIGHT + GAP
	end
	y = y + MESSAGE_HEIGHT

	y = y + HEADING_HEIGHT
	local full = cfg.sidebarWidth - 2 * PAD
	table.insert(out, { kind = "name", label = "Name", heading = "Design", x = PAD, y = y, width = full, height = DESIGN_ROW_HEIGHT })
	y = grid(out, screen, nil, {
		{ kind = "save", label = "Save" },
		{ kind = "new", label = "New" },
		{ kind = "open", label = "Open" },
	}, 3, DESIGN_ROW_HEIGHT, y + DESIGN_ROW_HEIGHT + GAP)

	local sections
	if screen.browsing then
		sections = {}
		for i, design in ipairs(Library.liveDesigns(screen.library)) do
			table.insert(sections, {
				kind = "expand",
				heading = i == 1 and "Open a design" or nil,
				columns = 1,
				height = DESIGN_LIST_HEIGHT,
				items = { { label = design.name .. "  v" .. Library.newestLive(design), value = design.id } },
			})
			if screen.expanded == design.id then
				local rows = { columns = 2, height = DESIGN_LIST_HEIGHT, items = {} }
				local live = Library.liveVersions(design)
				for j = #live, 1, -1 do
					local n = live[j]
					local armed = screen.armed and screen.armed.id == design.id and screen.armed.n == n
					table.insert(rows.items, { kind = "openVersion", label = "Open v" .. n, value = design.id, version = n })
					table.insert(rows.items, { kind = "deleteVersion", label = armed and "Confirm" or "Delete", value = design.id, version = n, armed = armed })
				end
				table.insert(sections, rows)
			end
		end
	else
		local plain = { kind = "shape", heading = "Brick (R turns)", columns = SHAPE_COLUMNS, height = SHAPE_HEIGHT, items = {} }
		local special = { kind = "shape", heading = "Function bricks", columns = 2, height = SHAPE_HEIGHT, items = {} }
		sections = {
			plain,
			special,
			{ kind = "material", heading = "Material", columns = 2, height = SHAPE_HEIGHT, items = {} },
			{ kind = "paint", heading = "Paint (shift-click)", columns = SWATCH_COLUMNS, height = SWATCH_HEIGHT, items = {} },
		}
		for _, shape in ipairs(cfg.bricks) do
			local hasRole = shape.ability or shape.port or shape.storage
			table.insert(hasRole and special.items or plain.items, { label = shape.label or shape.name, value = shape.name })
		end
		for _, material in ipairs(cfg.materials) do
			table.insert(sections[3].items, { label = capitalised(material), value = material })
		end
		for i in ipairs(cfg.palette) do
			table.insert(sections[4].items, { label = "paint:" .. i, value = i })
		end
	end
	for _, section in ipairs(sections) do
		local first = #out + 1
		local top = y + (section.heading and HEADING_HEIGHT or 0)
		y = grid(out, screen, section.kind, section.items, section.columns, section.height, top)
		if out[first] and section.heading then
			out[first].heading = section.heading
		end
	end
	return out
end

local function buttonAt(screen, x, y)
	for _, b in ipairs(BuilderScreen.buttons(screen)) do
		if x >= b.x and x < b.x + b.width and y >= b.y and y < b.y + b.height then
			return b
		end
	end
	return nil
end

-- What the cursor at (x, y) points at in the draft (Pick.cast), or nil.
function BuilderScreen.hover(screen, x, y)
	if x == nil or x < screen.cfg.sidebarWidth or x >= BuilderScreen.infoPanel(screen).x then
		return nil
	end
	local origin, dir = BuilderCamera.ray(BuilderScreen.view(screen), x, y)
	return Pick.cast(screen.draft, origin, dir, screen.cfg, screen.held)
end

local function changed(screen)
	screen.revision = screen.revision + 1
end

-- Runs a draft edit (Draft.place, ...) through the undo history, and
-- remeshes when it took. Returns the edit's results.
local function edit(screen, change, ...)
	local results = { History.apply(screen.history, screen.draft, change, ...) }
	if results[1] then
		changed(screen)
	end
	return unpack(results, 1, table.maxn(results))
end

local function resize(screen, b)
	local d = screen.draft
	local ok, reason = edit(screen, Draft.resize, d.width + b.dw, d.depth + b.dd, screen.cfg)
	screen.message = not ok and REFUSALS[reason] or nil
end

local function place(screen, x, y)
	local hit = BuilderScreen.hover(screen, x, y)
	if hit then
		edit(screen, Draft.place, hit.place.x, hit.place.y, hit.place.z, screen.cfg, screen.held)
	end
end

local function paint(screen, x, y)
	local hit = BuilderScreen.hover(screen, x, y)
	if hit and hit.brick then
		edit(screen, Draft.paint, hit.brick, screen.held.paint)
	end
end

local function remove(screen, x, y)
	local hit = BuilderScreen.hover(screen, x, y)
	if hit and hit.brick then
		edit(screen, Draft.remove, hit.brick)
	end
end

local function setTyping(screen, on)
	if screen.typingName ~= on then
		screen.typingName = on
		love.keyboard.setTextInput(on)
	end
end

-- Starts editing `draft` as design `id` (nil for a new design) named `name`.
-- Undo never reaches back into what was being edited before.
local function startEditing(screen, draft, id, name)
	screen.draft = draft
	screen.designId = id
	screen.name = name
	screen.history = History.new()
	screen.browsing = false
	changed(screen)
end

-- Saves the draft as the next version of its design (or a new design),
-- unless Library.canSave refuses it. Never checks what it would cost.
local function save(screen)
	local ok, reason = Library.canSave(screen.draft, screen.cfg)
	if not ok then
		screen.message = SAVE_REFUSALS[reason]
		return
	end
	local name = screen.name ~= "" and screen.name or DEFAULT_NAME
	local design, n = Library.save(screen.library, screen.designId, name, screen.draft)
	local written, err = DesignStore.write(screen.config.designs.dir, design)
	if not written then
		screen.message = "Could not save: " .. tostring(err)
		return
	end
	screen.designId, screen.name = design.id, design.name
	screen.message = string.format("Saved %s (version %d).", design.name, n)
end

-- Opens version `n` of library design `id` into the builder.
local function open(screen, id, n)
	local design = Library.design(screen.library, id)
	startEditing(screen, Library.toDraft(design.versions[n]), design.id, design.name)
	screen.message = string.format("Opened %s (version %d).", design.name, n)
end

-- Deletes version `n` of library design `id` and writes its file. When the
-- write fails the version stays live, so memory matches disk. The draft on
-- screen stays; when its design has no live version left, Save makes a new
-- design.
local function deleteVersion(screen, id, n)
	local design = Library.design(screen.library, id)
	Library.deleteVersion(screen.library, id, n)
	local written, err = DesignStore.write(screen.config.designs.dir, design)
	if not written then
		design.retired[n] = nil
		screen.message = "Could not delete: " .. tostring(err)
		return
	end
	if screen.designId == id and not Library.newestLive(design) then
		screen.designId = nil
	end
	screen.message = string.format("Deleted %s v%d.", design.name, n)
end

-- A Delete click: the first arms it, a second on the same row deletes.
-- `wasArmed` is what was armed before this click.
local function pressDelete(screen, b, wasArmed)
	if wasArmed and wasArmed.id == b.value and wasArmed.n == b.version then
		deleteVersion(screen, b.value, b.version)
		return
	end
	local design = Library.design(screen.library, b.value)
	screen.armed = { id = b.value, n = b.version }
	screen.message = string.format("Click again to delete %s v%d.", design.name, b.version)
end

local function press(screen, b, wasArmed)
	if b.kind == "resize" then
		resize(screen, b)
	elseif b.kind == "name" then
		setTyping(screen, true)
	elseif b.kind == "save" then
		save(screen)
	elseif b.kind == "new" then
		startEditing(screen, Draft.new(), nil, "")
		screen.message = nil
	elseif b.kind == "open" then
		screen.browsing = not screen.browsing
	elseif b.kind == "expand" then
		screen.expanded = screen.expanded ~= b.value and b.value or nil
	elseif b.kind == "openVersion" then
		open(screen, b.value, b.version)
	elseif b.kind == "deleteVersion" then
		pressDelete(screen, b, wasArmed)
	else
		screen.held[b.kind] = b.value
	end
end

-- Whether typed text and keys go to the design's name.
function BuilderScreen.typing(screen)
	return screen.typingName
end

-- The number of UTF-8 characters in `s`.
local function length(s)
	return select(2, s:gsub("[^\128-\191]", ""))
end

function BuilderScreen.textinput(screen, text)
	if screen.typingName and length(screen.name) + length(text) <= screen.config.designs.maxNameLength then
		screen.name = screen.name .. text
	end
end

-- Keys while typing a name: backspace deletes the last character; Enter or
-- Esc stops typing. Every other key is text, never a builder command.
local function typingKey(screen, key)
	if key == "backspace" then
		screen.name = screen.name:match("^(.-)[^\128-\191]?[\128-\191]*$")
	elseif key == "return" or key == "kpenter" or key == "escape" then
		setTyping(screen, false)
	end
end

-- Whether either of a modifier's keys ("ctrl", "shift") is held.
local function modifier(name)
	return love.keyboard.isDown("l" .. name) or love.keyboard.isDown("r" .. name)
end

function BuilderScreen.keypressed(screen, key)
	if screen.typingName then
		typingKey(screen, key)
	elseif key == "r" then
		screen.held.rotation = (screen.held.rotation + 1) % 4
	elseif key == "z" and modifier("ctrl") then
		local step = modifier("shift") and History.redo or History.undo
		if step(screen.history, screen.draft) then
			screen.message = nil
			changed(screen)
		end
	end
end

function BuilderScreen.mousepressed(screen, x, y, button)
	-- Any click disarms a Delete; only a second click on its row deletes.
	local wasArmed = screen.armed
	screen.armed = nil
	if button == 1 then
		local b = buttonAt(screen, x, y)
		setTyping(screen, b ~= nil and b.kind == "name")
		if b then
			press(screen, b, wasArmed)
		elseif modifier("shift") then
			paint(screen, x, y)
		else
			place(screen, x, y)
		end
	elseif button == 2 then
		screen.rightPress = { x = x, y = y, moved = 0 }
	end
end

-- A right release that barely moved is a click: remove the brick under it.
function BuilderScreen.mousereleased(screen, x, y, button)
	local press = screen.rightPress
	if button == 2 and press then
		screen.rightPress = nil
		if press.moved < screen.cfg.clickSlop then
			remove(screen, x, y)
		end
	end
end

function BuilderScreen.mousemoved(screen, x, y, dx, dy)
	screen.mouseX, screen.mouseY = x, y
	local press = screen.rightPress
	if press then
		press.moved = press.moved + math.abs(dx) + math.abs(dy)
		if press.moved >= screen.cfg.clickSlop then
			BuilderCamera.orbit(screen.camera, dx, dy, screen.cfg)
		end
	end
end

function BuilderScreen.wheelmoved(screen, _, y)
	BuilderCamera.zoomBy(screen.camera, y, screen.draft, screen.cfg)
end

function BuilderScreen.draw(screen)
	local hit = BuilderScreen.hover(screen, screen.mouseX, screen.mouseY)
	local ghost = nil
	if hit and Draft.fits(screen.draft, hit.place.x, hit.place.y, hit.place.z, screen.cfg, screen.held) then
		ghost = hit.place
	end
	BuilderView.draw(screen, BuilderScreen.view(screen), ghost)
	BuilderView.drawSidebar(screen, BuilderScreen.buttons(screen))
	BuilderView.drawInfo(screen, BuilderScreen.infoPanel(screen), BuilderScreen.info(screen))
end

return BuilderScreen
