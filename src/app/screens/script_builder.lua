-- The script builder (docs/CONTEXT.md § Script builder): a live 3D view of
-- a design script's geometry through the orbit camera, its footprint on the
-- ground (with an always-on whole-tile ground grid 8 tiles round the design
-- origin, a 1x1 tile guide and X red, Y green, Z blue axes, all under the
-- geometry), the numbered tool bar along the top, and the tree panel naming
-- its nodes down the left.
--
-- Opening it reads the design named after config.scriptBuilder.testDesign's
-- file -- the player's saved copy in the design library if there is one,
-- else the file itself -- and checks it (src/game/script/lockcheck.lua):
-- a declarative script becomes an editable scene (src/game/builder/scene.lua),
-- a script holding code is locked and only viewed. The geometry shown is
-- the scene's tree written out (src/game/script/serialize.lua) and compiled
-- (src/game/buildings/compile.lua: sandboxed, its prefabs resolved from the
-- design library) into a blueprint. A script that fails shows its message
-- instead.
--
-- A click on a tree row, on the model, within 10 px of a shape outline or path
-- line, or inside a closed shape selects its node (outlines beat the model;
-- the one within reach lights up on hover), Ctrl-click adds
-- to the selection, and a double-click on a row renames it. A right-click
-- without movement opens the context menu, listing only the actions that
-- apply to the selection (src/game/builder/actions.lua); a bare shape or
-- path gets Make 3D, which opens Extrude, Lathe and the two ways to sweep
-- (shape then path, or path then shape) in place; right-drag orbits, the wheel zooms. The action panel under the
-- tree lists the same actions (or a hint with nothing selected) and its
-- buttons run the same handlers. Number keys and clicks pick
-- top bar tools: 1 Select, 2 Draw (shapes and paths in one menu), 3 Insert,
-- 4 Code, 5 Library. Ctrl+Z undoes, Ctrl+Y or Ctrl+Shift+Z redoes, Ctrl+S
-- saves the design file (src/app/design_store.lua); a locked script saves
-- as it was read, never regenerated. The builder never touches the world.
--
-- G, R and S move, rotate and scale the selection (src/game/builder/transform.lua)
-- with the pointer, X, Y and Z holding it to an axis and Shift freeing it
-- from the snap; a left click or Return keeps it, Esc or a right click
-- drops it. They also pick what the gizmo (src/app/render/gizmo.lua) on the
-- selection does: dragging one of its handles runs that transform on the
-- handle's axis until the button comes up. Each kept transform is one undo
-- step; while one runs the view holds still and the design rebuilds live.
--
-- While drawing a polygon or freeform outline, Return or a double-click
-- closes it (last point joins the first) and finishes an open path; the
-- first point grows and lights under the pointer, and a hint line names
-- the controls (ScriptBuilderScreen.hint).
--
-- Key 2 (Insert) opens a menu of primitives and prefabs, role prefabs
-- included (src/game/builder/insert.lua); a click on one arms it and a
-- click in the view places it on the work plane under the pointer (the
-- ground, snapped to a quarter tile unless Shift is held), selected, as one
-- undo step. Esc puts the tool away. The properties strip along the top
-- right edits the one selected primitive's dimensions and segments
-- (src/game/builder/properties.lua): a click on a box opens it as text,
-- Return keeps it as one undo step, Esc drops it.
--
-- The params panel down the right edge (src/app/ui/params_panel.lua) has an
-- input per UI.* param the script declares (src/game/script/params.lua):
-- a number's - and + step it, a click on a value box types a number (or a
-- colour's "r g b"), a bool toggles and a choice steps to its next option.
-- A change rewrites that param's default in the script's text -- the one
-- edit a locked script takes; scripts with params are always locked -- and
-- rebuilds the model live, so Ctrl+S saves the new default.
--
-- Key 1 (Draw: shapes) draws a closed 2D outline (src/game/builder/shape_tool.lua)
-- on the work plane (src/game/builder/work_plane.lua): the ground, an XY,
-- XZ or YZ plane at a height ([ and ] step it by a quarter tile) or a face
-- of the model picked from its menu. A rect or ellipse takes two clicks on
-- opposite corners; a polygon or path takes a click per point, and a path
-- point dragged while placed turns smooth with Bézier handles. Clicking
-- the first point again closes the outline into a shape node, one undo
-- step. Esc drops the outline being drawn, then puts the tool away. Shapes
-- show as outlines with no volume; the selected shape's points drag along
-- its plane, each move one undo step. The quarter-tile grid shows while Shape or
-- Insert is on, snapping to a quarter tile unless Shift is held; Insert
-- places on the same work plane.
--
-- Key 1 (Draw: paths) draws an open path (src/game/builder/path_tool.lua) on the
-- same work planes, from the same kind of menu: a line takes two clicks,
-- an arc its centre, start and end (counter-clockwise), a helix its centre
-- and radius; a polyline, Bézier (drag while placing for handles) or
-- Catmull-Rom takes clicks until Return or a click on its last point
-- again. Each path is one undo step. Right-click a shape and pick Sweep,
-- then click a path (in the view or its tree row): the shape sweeps along
-- it (src/game/geometry/sweep.lua), one undo step; Esc drops the Sweep.
-- The properties strip edits a sweep's twist and scales and an arc's or
-- helix's params.
--
-- Material and Colour are sections beside the action panel, shown only
-- while the selection has volume (Actions.showPaint). They sit at the top
-- of the view so a tall tree never pushes them off a small window. The
-- material section (src/app/ui/material_panel.lua) shows the first selected
-- node's material (its own or inherited, else the default). A click on a
-- material, a texture variant, or a scale or rotation stepper makes every
-- selected node with volume of the result (Scene.setMaterial), one undo
-- step. The colour section (src/app/ui/colour_picker.lua) has the team
-- slots (drawn in the local player's palette), preset colours and the
-- recent picks (the last 8, this session only). A click paints every
-- selected node with volume that slot or colour (Scene.setColor), one undo
-- step. A shape or path alone shows neither.
--
-- Prefabs (docs/CONTEXT.md "Prefab"): Export as prefab in the context menu
-- asks for a name, writes prefabs/<name>.lua and turns the selection into
-- one instance of it (Scene.export), one undo step; a locked script
-- refuses. A selected instance lists its prefab's tree read-only under its
-- row (a click there selects the instance), and the params panel shows its
-- prefab's params, a change overriding them on the instance
-- (Scene.setParam); its material and colour cover all of it. Unlink
-- replaces it with an editable copy (Scene.unlink), except a role prefab.
-- Edit prefab opens the instance's prefab here; Ctrl+S then writes it, a
-- built-in as a shadow copy in the save directory, and Reset to default
-- deletes that copy (Library.reset).
--
-- Key 4 (Library) opens the library manager (src/app/ui/library_panel.lua)
-- under its slot: Designs and Prefabs tabs listing every script with a
-- thumbnail and Open, Duplicate, Rename and Delete (Reset for a built-in,
-- which can't be renamed or deleted); Delete takes a second click to
-- confirm. New starts an empty design. Renaming or deleting changes no
-- script that places it by name: that script fails to load, naming it.
-- Whatever would switch the open script away from unsaved changes (Open,
-- New, Edit prefab, Reset of the open script) asks first: S saves, D
-- drops them, Esc stays. Esc puts the panel away.
--
-- Key 3 (Code) opens the code panel (src/app/ui/code_panel.lua) down the
-- right: the script as text (src/game/text_buffer.lua) with line numbers.
-- While it is up every key types or edits there (digits pick no tool);
-- a click places the cursor, a drag or Shift selects, Ctrl+C/X/V/A copy,
-- cut, paste and select all, the wheel scrolls. Ctrl+Enter (or Run) runs
-- the text as the script: declarative it stays editable, with code it
-- locks; an error marks its line and keeps the last good model. Code not
-- yet run is an unsaved change; Ctrl+S runs it first. Open folder opens
-- the save folder for an external editor and shows its path. Esc puts the
-- panel away, its text kept.
--
-- Hot reload: twice a second the builder looks for changed files in the
-- save directory (DesignStore.stamp). The open script, changed on disk,
-- opens again as it now reads, unless it has unsaved changes: those are
-- kept and the message says the file changed. A changed prefab rebuilds
-- the model.
local Compile = require("src.game.buildings.compile")
local Resolve = require("src.game.script.resolve")
local Lockcheck = require("src.game.script.lockcheck")
local Serialize = require("src.game.script.serialize")
local Scene = require("src.game.builder.scene")
local Actions = require("src.game.builder.actions")
local History = require("src.game.builder.history")
local Mesh = require("src.game.geometry.mesh")
local Pick = require("src.game.geometry.pick")
local Transform = require("src.game.builder.transform")
local Insert = require("src.game.builder.insert")
local WorkPlane = require("src.game.builder.work_plane")
local ShapeTool = require("src.game.builder.shape_tool")
local PathTool = require("src.game.builder.path_tool")
local Path = require("src.game.geometry.path")
local Shape2d = require("src.game.geometry.shape2d")
local Properties = require("src.game.builder.properties")
local Params = require("src.game.script.params")
local Library = require("src.game.designs.library")
local BuilderCamera = require("src.app.builder_camera")
local DesignStore = require("src.app.design_store")
local ScriptBuilderView = require("src.app.render.script_builder_view")
local Gizmo = require("src.app.render.gizmo")
local WorkPlaneView = require("src.app.render.work_plane")
local ShapeOverlay = require("src.app.render.shape_overlay")
local TopBar = require("src.app.ui.top_bar")
local TreePanel = require("src.app.ui.tree_panel")
local ActionPanel = require("src.app.ui.action_panel")
local BuilderColumn = require("src.app.ui.builder_column")
local ContextMenu = require("src.app.ui.context_menu")
local InsertMenu = require("src.app.ui.insert_menu")
local PropertiesStrip = require("src.app.ui.properties")
local WorkPlaneSection = require("src.app.ui.work_plane_section")
local ParamsPanel = require("src.app.ui.params_panel")
local MaterialPanel = require("src.app.ui.material_panel")
local Dropdown = require("src.app.ui.dropdown")
local ColourPicker = require("src.app.ui.colour_picker")
local LibraryPanel = require("src.app.ui.library_panel")
local CodePanel = require("src.app.ui.code_panel")
local TextBuffer = require("src.game.text_buffer")
local Sandbox = require("src.game.script.sandbox")
local BuildingsRender = require("src.app.render.buildings")
local RecentColours = require("src.game.builder.recent_colours")
local Palette = require("src.game.palette")
local Screen = require("src.app.screen")

local ScriptBuilderScreen = {}

-- The top bar's tools by slot number.
ScriptBuilderScreen.TOOLS = {
	[1] = { id = "draw", label = "Draw" },
	[2] = { id = "insert", label = "Insert" },
	[3] = { id = "code", label = "Code" },
	[4] = { id = "library", label = "Library" },
}

-- The Draw tool's menu: closed shapes, then open paths, each under a header
-- (a header row has `header` and is not pickable).
local DRAW_KINDS = { { header = true, label = "Shapes (closed)" } }
for _, kind in ipairs(ShapeTool.KINDS) do
	DRAW_KINDS[#DRAW_KINDS + 1] = kind
end
DRAW_KINDS[#DRAW_KINDS + 1] = { header = true, label = "Paths (open)" }
for _, kind in ipairs(PathTool.KINDS) do
	DRAW_KINDS[#DRAW_KINDS + 1] = kind
end

-- The camera's radius around an empty design, in studs.
local EMPTY_RADIUS = 4

-- A right-button press that moves less than this, in pixels, is a click
-- (the menu); more is an orbit.
local CLICK_SLOP = 4

-- The keys that start each transform, and the axis keys.
local TRANSFORM_KEYS = { g = "move", r = "rotate", s = "scale" }
local AXIS_KEYS = { x = true, y = true, z = true }

-- How near, in pixels, a click must come to an outline's first point to
-- close it, or to a selected shape's point to drag it.
local POINT_REACH = 10

-- How far the work plane's grid reaches round the pointer, in tiles.
local GRID_EXTENT = 3
-- Tiles the always-on ground grid reaches each way of the design origin.
local GROUND_EXTENT = 8

-- Two left clicks on one row within this many seconds rename it.
local DOUBLE_CLICK = 0.4

local LOCKED_MESSAGE = "Locked script: it holds code, so edit it as text"

-- Seconds between hot reload's looks at the save directory.
local POLL = 0.5

-- Px the builder column scrolls per wheel notch.
local WHEEL_STEP = 30

-- read(path) returns a game file's text, or nil and why not
-- (love.filesystem.read). library() returns the design library as it is
-- now (src/game/designs/library.lua), which its prefabs resolve from.
-- palette: returns the local player's team palette (src/game/palette.lua),
-- which the view draws team slots in; default Palette.DEFAULT.
function ScriptBuilderScreen.new(config, read, library, palette)
	return {
		config = config,
		palette = palette or function()
			return Palette.DEFAULT
		end,
		-- The colour picker's recent picks (RecentColours), kept across
		-- openings for the session.
		recentColours = RecentColours.new(),
		-- The builder column's state (BuilderColumn), kept across openings:
		-- collapsed sections by name, the scroll in px, and a thumb drag
		-- ({ grab }) in progress.
		column = { collapsed = {}, scroll = 0, dragging = nil },
		cfg = config.builder,
		scfg = config.scriptBuilder,
		read = read,
		library = library,
		camera = BuilderCamera.new(config.builder),
		-- The design library this opening reads prefabs from.
		lib = nil,
		-- What is open: a design or a prefab ("designs" | "prefabs").
		kind = "designs",
		-- The design's name, what its messages call it (the file path when
		-- read from one), its text as read, and whether it is locked.
		name = nil,
		chunk = nil,
		source = nil,
		locked = false,
		-- The edited tree and its selection (Scene), and its undo history;
		-- scene is nil when the script failed to run.
		scene = nil,
		history = History.new(),
		-- The design's clipped geometry (Mesh), its bounds and footprint, in
		-- tiles; bounds and footprint are nil when it has no geometry.
		triangles = {},
		bounds = nil,
		footprint = nil,
		-- The same geometry by the node a click on it selects (Pick.targets),
		-- clipped and in the blueprint's space.
		targets = {},
		-- Where the blueprint's space starts in the design's own: { x, y }
		-- tiles (the clipped geometry's north-west corner).
		origin = { 0, 0 },
		-- What dragging a gizmo handle does: "move", "rotate" or "scale".
		gizmoMode = "move",
		-- The transform under way, or nil: { drag (Transform.start), amount,
		-- before (the scene's root as it was), view and origin when it
		-- began, gizmo (true when a handle drag) }.
		transform = nil,
		-- The blueprint's ports (Blueprint roles.ports), snapped to the
		-- footprint edge.
		ports = {},
		-- Bumped whenever the geometry or selection changes, so the view
		-- rebuilds only then.
		revision = 0,
		-- Why the design could not be shown or an edit was refused, or nil.
		message = nil,
		-- What the last save did, or nil.
		status = nil,
		tool = "select",
		-- While the Insert tool is on: { items (Insert.items), armed (the
		-- item a click in the view places, or nil) }; else nil.
		insert = nil,
		-- The properties strip's text box { id, key, text } while open, or
		-- nil.
		field = nil,
		-- The params the script declares (Params.collect) as of its last
		-- good run, and the params panel's text box { index, text, initial }
		-- while open, or nil.
		params = {},
		paramField = nil,
		-- The plane shapes are drawn and things inserted on (WorkPlane), what
		-- the Shape menu calls it ("Ground", "XY", "XZ", "YZ" or "Face"),
		-- and an axis plane's height in tiles.
		plane = WorkPlane.ground(),
		planeName = "Ground",
		planeHeight = 0,
		-- While the Draw tool is on: { kinds (ShapeTool.KINDS or
		-- PathTool.KINDS), kind (one of them), path (true for the Path
		-- tool), drawing (the outline or path under way { points, anchor (a
		-- rect or ellipse's first corner), dragging (the index of the point
		-- whose handle the held button drags) } or nil), picking (true while
		-- the next click adopts a face) }; else nil.
		shape = nil,
		-- After Sweep, until a path is clicked: { id (the shape's) }, or nil.
		sweeping = nil,
		-- Where the pointer meets the work plane, { a, b } in its
		-- coordinates, or nil.
		hover = nil,
		-- A selected shape's point being dragged: { id, index, plane (the
		-- shape's, in design space), before (the scene's root as it was),
		-- at } or nil.
		pointDrag = nil,
		-- The context menu (ContextMenu) while open, or nil.
		menu = nil,
		-- The rename text box { id, text } while open, or nil.
		rename = nil,
		-- Export as prefab's name prompt { text } while open, or nil.
		exportPrompt = nil,
		-- The library manager while open: { tab ("designs" | "prefabs"),
		-- entries (Library.entries, each with the blueprint its thumbnail
		-- shows, or none), armed (the name whose Delete awaits its second
		-- click, or nil) }; else nil.
		libraryOpen = nil,
		-- The manager's Rename prompt { kind, name, text } while open, or nil.
		libraryRename = nil,
		-- The code panel's state, kept while the panel is put away: { open,
		-- buffer (TextBuffer), scroll (lines scrolled down), base (the
		-- buffer's text when last opened or run: edits since are unsaved),
		-- shown (text() then: when it has changed, the panel opens afresh),
		-- errorLine (the line the last error points at, or nil), openedAt
		-- (the clock when opened: that frame's textinput is the opening
		-- key's), dragging (true while a left drag selects) }; nil until
		-- first opened on the script.
		code = nil,
		-- The unsaved-changes prompt { go (what switching does) } while
		-- open, or nil.
		unsaved = nil,
		-- The script's text as last opened or saved: it is dirty when its
		-- text (text()) differs.
		saved = nil,
		-- Each prefab instance's own tree as last resolved, by the
		-- instance's id: the tree panel shows a selected one's read-only.
		expanded = {},
		-- The selected instance's params (Resolve.prefab), worked out once
		-- per revision: { revision, id, params }, or nil.
		instanceCache = nil,
		-- The right button's press { x, y, moved } while held, or nil.
		rightPress = nil,
		-- Seconds since the screen was made, and the last left click on a
		-- row { id, time }, for double-clicks.
		clock = 0,
		lastClick = nil,
		mouse = nil,
	}
end

-- `triangles` clipped at the ground and moved by (dx, dy).
local function placed(triangles, dx, dy)
	return Mesh.transform(Mesh.clip(triangles), { move = { dx, dy, 0 } })
end

-- Shows `blueprint` of resolved tree `root`, or nothing and `message`.
local function show(screen, blueprint, root, message)
	screen.blueprint = blueprint
	screen.triangles = blueprint and blueprint.mesh or {}
	screen.bounds = Mesh.bounds(screen.triangles)
	screen.footprint = blueprint and { x = 0, y = 0, width = blueprint.width, depth = blueprint.depth }
	screen.ports = blueprint and blueprint.roles.ports or {}
	screen.targets = {}
	screen.origin = { 0, 0 }
	if blueprint then
		local targets = Pick.targets(Scene.ensureIds(root))
		local all = {}
		for i, t in ipairs(targets) do
			all[i] = Mesh.clip(t.triangles)
		end
		local b = Mesh.bounds(Mesh.merge(all))
		screen.origin = { b.minX, b.minY }
		for i, t in ipairs(targets) do
			screen.targets[i] = { id = t.id, triangles = placed(t.triangles, -b.minX, -b.minY) }
		end
	end
	screen.message = message
	screen.revision = screen.revision + 1
end

-- The design's text as it stands: as read when locked, else the scene's
-- tree written out.
local function text(screen)
	if screen.locked or not screen.scene then
		return screen.source
	end
	return Serialize.tree(screen.scene.root)
end

-- Compiles the design as it stands and shows it.
local function rebuild(screen, message)
	local source = text(screen)
	local resolved, reason = Resolve.design(source, screen.chunk, screen.lib)
	if not resolved then
		show(screen, nil, nil, reason)
		return
	end
	screen.params = Params.collect(source, resolved.params)
	screen.expanded = {}
	local function instances(node)
		if node.kind == "prefab" then
			screen.expanded[node.id or ""] = node.children[1]
			return
		end
		for _, child in ipairs(node.children or {}) do
			instances(child)
		end
	end
	instances(resolved.root)
	local blueprint, why = Compile.blueprint(resolved.root, screen.config)
	show(screen, blueprint, resolved.root, why or message)
end

-- The design name of a file path: its file name without ".lua".
local function nameOf(path)
	return path:match("([^/]+)%.lua$") or path
end

-- Reads and checks script `name` of `kind` ("designs" | "prefabs") from
-- the design library, else (a design only) from game file `path`, showing
-- it or why it failed. A built-in opens as shipped unless the save
-- directory shadows it; saving writes the shadow. `given`, when given, is
-- the script's text instead (a New design, not yet saved).
local function readScript(screen, kind, name, path, given)
	screen.kind, screen.name = kind, name
	screen.lib = screen.library()
	screen.scene, screen.history, screen.locked = nil, History.new(), false
	screen.menu, screen.rename, screen.status, screen.transform = nil, nil, nil, nil
	screen.tool, screen.insert, screen.field = "select", nil, nil
	screen.shape, screen.pointDrag, screen.hover, screen.sweeping = nil, nil, nil, nil
	screen.plane, screen.planeName, screen.planeHeight = WorkPlane.ground(), "Ground", 0
	screen.params, screen.paramField = {}, nil
	screen.libraryOpen = nil
	screen.exportPrompt, screen.libraryRename, screen.unsaved = nil, nil, nil
	screen.code = nil
	local source, err = given or screen.lib[kind][name], "not in the library"
	screen.chunk, screen.path = name, path
	if not source and path then
		source, err = screen.read(path)
		screen.chunk = path
	end
	screen.source = source
	screen.diskText = not given and source or nil
	if not source then
		show(screen, nil, nil, "Can't read " .. (path or name) .. ": " .. tostring(err))
		return
	end
	local checked, reason = Lockcheck.check(source, screen.chunk)
	if not checked then
		show(screen, nil, nil, reason)
		return
	end
	screen.scene = Scene.new(checked.root)
	screen.locked = checked.locked
	rebuild(screen)
end

local function openScript(screen, kind, name, path, given)
	readScript(screen, kind, name, path, given)
	screen.saved = text(screen)
end

-- Whether the code panel holds edits not yet run.
local function unrun(screen)
	return screen.code ~= nil and TextBuffer.text(screen.code.buffer) ~= screen.code.base
end

-- Whether the open script has changes not saved: its text as it stands
-- differs from what was last opened or saved, or the code panel holds
-- edits not yet run.
function ScriptBuilderScreen.dirty(screen)
	return text(screen) ~= screen.saved or unrun(screen)
end

-- Reads and checks the design named after config.scriptBuilder.testDesign's
-- file.
function ScriptBuilderScreen.open(screen)
	local path = screen.scfg.testDesign
	screen.stamp = DesignStore.stamp(screen.config.designs)
	screen.pollIn = POLL
	openScript(screen, "designs", nameOf(path), path)
end

-- Whether a menu or text box has the keyboard: Esc closes it, not the
-- builder.
function ScriptBuilderScreen.modal(screen)
	return screen.menu ~= nil or screen.rename ~= nil or screen.transform ~= nil
		or screen.field ~= nil or screen.insert ~= nil or screen.paramField ~= nil
		or screen.shape ~= nil or screen.pointDrag ~= nil or screen.sweeping ~= nil
		or screen.exportPrompt ~= nil or ScriptBuilderScreen.dropdown(screen) ~= nil
		or screen.libraryOpen ~= nil or screen.libraryRename ~= nil or screen.unsaved ~= nil
		or (screen.code ~= nil and screen.code.open)
end

-- Runs scene edit `change` (a Scene function) through the undo history and
-- shows the result; a locked script refuses every edit.
local function edit(screen, change, ...)
	if screen.locked then
		screen.message = LOCKED_MESSAGE
		return
	end
	local ok, reason = History.apply(screen.history, screen.scene, change, ...)
	rebuild(screen, not ok and reason or nil)
end

local function undo(screen, step)
	if screen.scene and step(screen.history, screen.scene) then
		rebuild(screen)
	end
end

-- Writes the design or prefab file: the scene written out, or the locked
-- script as it was read.
local function save(screen)
	if unrun(screen) and not ScriptBuilderScreen.runCode(screen) then
		screen.status = "Save failed: the code has an error"
		return
	end
	if not screen.source then
		return
	end
	local ok, err = DesignStore.write(screen.config.designs, screen.kind, screen.name, text(screen))
	if ok then
		screen.saved = text(screen)
		screen.diskText = screen.saved
		screen.status = "Saved " .. screen.name .. (screen.locked and " (locked: code kept as written)" or "")
	else
		screen.status = "Save failed: " .. tostring(err)
	end
end

-- The 3D view's rectangle: the window below the top bar.
function ScriptBuilderScreen.viewport(screen)
	local w, h = Screen.dimensions()
	local top = screen.scfg.topBarHeight
	return { x = 0, y = top, width = w, height = h - top }
end

-- The numbered top bar slots (TopBar.slots), left to right.
function ScriptBuilderScreen.topBar(screen)
	return TopBar.slots(screen.scfg.topBarHeight, screen.scfg.topBarSlots, ScriptBuilderScreen.TOOLS)
end

-- The prefab instances' trees shown read-only under the selection.
local function expandedTrees(screen)
	local expanded = {}
	for _, id in ipairs(screen.scene.selection) do
		expanded[id] = screen.expanded[id]
	end
	return expanded
end

-- The action panel's labels: the selection's actions (Actions.of), Make 3D's
-- second level once opened, or nil (the hint) with nothing selected.
local function actionItems(screen)
	local scene = screen.scene
	if #scene.selection == 0 then
		return nil
	end
	local sub = screen.panelSub
	if sub and sub.id == scene.selection[1] and #scene.selection == 1 then
		return sub.items
	end
	screen.panelSub = nil
	return Actions.of(scene, scene.selection, screen.lib, screen.locked)
end

-- Whether the Material and Colour sections show: the selection has volume
-- and the script can be edited.
local function paintShown(screen)
	return screen.scene ~= nil and not screen.locked and Actions.showPaint(screen.scene, screen.scene.selection)
end

-- The material the panel shows: the first selected node's (Scene.material),
-- else the default material's first variant, unscaled and unturned.
local function shownMaterial(screen)
	local id = screen.scene.selection[1]
	local material = id and Scene.material(screen.scene, id)
	if material then
		return material
	end
	local name = screen.config.blueprints.defaultMaterial
	return { name = name, variant = screen.config.materials[name].variants[1], scale = 1, rotation = 0 }
end

-- The selected node's editable properties (Properties.of); none unless
-- exactly one is selected and the script can be edited.
local function shownProperties(screen)
	local scene = screen.scene
	if screen.locked or not scene or #scene.selection ~= 1 then
		return {}
	end
	local node = Scene.find(scene, scene.selection[1])
	return node and Properties.of(node) or {}
end

-- The one selected node when it is a prefab instance, else nil.
local function selectedInstance(screen)
	local scene = screen.scene
	if not scene or #scene.selection ~= 1 then
		return nil
	end
	local node = Scene.find(scene, scene.selection[1])
	return node and node.kind == "prefab" and node or nil
end

-- The params the panel shows: the script's own when it declares any, else
-- the one selected prefab instance's (Resolve.prefab, its overrides as
-- values), worked out once per revision; and that instance, or nil.
local function shownParams(screen)
	if #screen.params > 0 then
		return screen.params, nil
	end
	local node = not screen.locked and selectedInstance(screen)
	if not node then
		return {}, nil
	end
	local c = screen.instanceCache
	if not (c and c.revision == screen.revision and c.id == node.id) then
		local result = Resolve.prefab(screen.lib, node.prefab, node.params)
		c = { revision = screen.revision, id = node.id, params = result and result.params or {} }
		screen.instanceCache = c
	end
	return c.params, node
end

-- The builder column's layout (BuilderColumn.layout): the Tree and Actions
-- sections under the top bar, scrolled; empty when the script failed.
function ScriptBuilderScreen.column(screen)
	local state = screen.column
	local sections = {}
	if screen.scene then
		local count = #TreePanel.rows(screen.scene, 0, expandedTrees(screen))
		sections = {
			{ name = "tree", title = "Tree", height = TreePanel.height(count), collapsed = state.collapsed.tree },
			{
				name = "actions",
				title = "Actions",
				height = ActionPanel.height(actionItems(screen)),
				collapsed = state.collapsed.actions,
			},
		}
		if screen.shape or screen.insert then
			table.insert(sections, 1, {
				name = "plane",
				title = "Work plane",
				height = WorkPlaneSection.height(screen.planeName),
				collapsed = state.collapsed.plane,
			})
		end
		local props = #shownProperties(screen)
		if props > 0 then
			sections[#sections + 1] = {
				name = "properties",
				title = "Properties",
				height = PropertiesStrip.height(props),
				collapsed = state.collapsed.properties,
			}
		end
		local params = #(shownParams(screen))
		if params > 0 then
			sections[#sections + 1] = {
				name = "params",
				title = "Params",
				height = ParamsPanel.height(params),
				collapsed = state.collapsed.params,
			}
		end
		if paintShown(screen) then
			sections[#sections + 1] = {
				name = "material",
				title = "Material",
				height = MaterialPanel.height(),
				collapsed = state.collapsed.material,
			}
			sections[#sections + 1] = {
				name = "colour",
				title = "Colour",
				height = ColourPicker.layout(ColourPicker.builderSections(screen.recentColours), 0, 0).height,
				collapsed = state.collapsed.colour,
			}
		end
	end
	local top = screen.scfg.topBarHeight
	local _, h = Screen.dimensions()
	local col = BuilderColumn.layout(sections, top, h - top, state.scroll)
	state.scroll = col.scroll
	return col
end

local function sectionContent(col, name)
	for _, s in ipairs(col.sections) do
		if s.name == name then
			return s.content
		end
	end
	return nil
end

-- The Work plane section's layout (WorkPlaneSection.layout) while Draw or
-- Insert is on; nil when neither is or the section is collapsed.
function ScriptBuilderScreen.workPlane(screen)
	if not (screen.shape or screen.insert) then
		return nil
	end
	local content = sectionContent(ScriptBuilderScreen.column(screen), "plane")
	return content and WorkPlaneSection.layout(screen.planeName, screen.planeHeight, content)
end

-- The tree panel's rows (TreePanel.rows), a selected prefab instance's
-- own tree read-only under it; none when the script failed or Tree is
-- collapsed.
function ScriptBuilderScreen.treeRows(screen)
	if not screen.scene then
		return {}
	end
	local content = sectionContent(ScriptBuilderScreen.column(screen), "tree")
	if not content then
		return {}
	end
	return TreePanel.rows(screen.scene, content.y, expandedTrees(screen))
end

-- What the camera circles, in studs: the middle of the geometry and its
-- footprint, and the radius holding both.
local function frame(screen)
	local b, f = screen.bounds, screen.footprint
	if not b then
		return { 0, 0, 0 }, EMPTY_RADIUS
	end
	local s = screen.cfg.studsPerTile
	local minX, minY = math.min(b.minX, f.x), math.min(b.minY, f.y)
	local maxX, maxY = math.max(b.maxX, f.x + f.width), math.max(b.maxY, f.y + f.depth)
	local hw, hd, hh = (maxX - minX) / 2, (maxY - minY) / 2, b.maxZ / 2
	return { (minX + hw) * s, (minY + hd) * s, hh * s }, math.sqrt(hw * hw + hd * hd + hh * hh) * s
end

-- This frame's camera view (src/app/builder_camera.lua), in studs. While a
-- transform runs it is the view it began with, its eye shifted with the
-- blueprint's origin so what stays put draws still.
function ScriptBuilderScreen.view(screen)
	local t = screen.transform
	if t then
		local s, v = screen.cfg.studsPerTile, {}
		for k, x in pairs(t.view) do
			v[k] = x
		end
		v.eye = {
			t.view.eye[1] + (t.origin[1] - screen.origin[1]) * s,
			t.view.eye[2] + (t.origin[2] - screen.origin[2]) * s,
			t.view.eye[3],
		}
		return v
	end
	local center, radius = frame(screen)
	return BuilderCamera.viewAround(screen.camera, center, radius, screen.cfg, ScriptBuilderScreen.viewport(screen))
end

-- The id of the node whose geometry is under screen point (x, y), or nil.
local function pickAt(screen, x, y)
	local origin, direction = BuilderCamera.ray(ScriptBuilderScreen.view(screen), x, y)
	local s = screen.cfg.studsPerTile
	return (Pick.at(screen.targets, { origin[1] / s, origin[2] / s, origin[3] / s }, direction))
end

-- How far screen point (x, y) lies from the segment between pixels a and
-- b ({ x, y } each).
local function fromSegment(x, y, a, b)
	local dx, dy = b[1] - a[1], b[2] - a[2]
	local len2 = dx * dx + dy * dy
	local t = len2 > 0 and math.max(0, math.min(1, ((x - a[1]) * dx + (y - a[2]) * dy) / len2)) or 0
	local px, py = a[1] + dx * t - x, a[2] + dy * t - y
	return math.sqrt(px * px + py * py)
end

-- The drawn points of `corners` (design space) as screen pixels, the first
-- again at the end when `closed`.
local function drawnPixels(screen, corners, closed)
	local view, s = ScriptBuilderScreen.view(screen), screen.cfg.studsPerTile
	local out = {}
	for _, point in ipairs(corners) do
		local px, py = WorkPlaneView.pixel(view, s, screen.origin, point)
		out[#out + 1] = px and { px, py } or false
	end
	if closed and #out > 0 then
		out[#out + 1] = out[1]
	end
	return out
end

-- Whether screen point (x, y) lies inside the closed polygon of pixels.
local function insidePixels(x, y, pixels)
	local inside = false
	for i = 1, #pixels - 1 do
		local a, b = pixels[i], pixels[i + 1]
		if a and b and (a[2] > y) ~= (b[2] > y) and x < (b[1] - a[1]) * (y - a[2]) / (b[2] - a[2]) + a[1] then
			inside = not inside
		end
	end
	return inside
end

-- The id of the path (or, with `shapes`, the closed shape) drawn nearest
-- screen point (x, y), within reach of its line; else, for shapes, one
-- whose outline holds the point; else nil.
local function outlineAt(screen, x, y, shapes)
	local best, nearest = nil, POINT_REACH
	local function consider(id, corners, closed)
		local pixels = drawnPixels(screen, corners, closed)
		for i = 2, #pixels do
			if pixels[i] and pixels[i - 1] then
				local d = fromSegment(x, y, pixels[i - 1], pixels[i])
				if d <= nearest then
					best, nearest = id, d
				end
			end
		end
	end
	for _, p in ipairs(WorkPlane.paths(screen.scene.root)) do
		consider(p.id, p.points, false)
	end
	if shapes then
		for _, s in ipairs(WorkPlane.shapes(screen.scene.root)) do
			consider(s.id, s.outline, true)
		end
		if not best then
			for _, s in ipairs(WorkPlane.shapes(screen.scene.root)) do
				if insidePixels(x, y, drawnPixels(screen, s.outline, true)) then
					return s.id
				end
			end
		end
	end
	return best
end

-- The path drawn nearest screen point (x, y), within reach, or nil.
local function pathAt(screen, x, y)
	return outlineAt(screen, x, y, false)
end

-- The action panel's layout (ActionPanel.layout) in the column's Actions
-- section; nil while it is collapsed.
function ScriptBuilderScreen.actionPanel(screen)
	local content = sectionContent(ScriptBuilderScreen.column(screen), "actions")
	if not content then
		return nil
	end
	return ActionPanel.layout(actionItems(screen), content.y)
end

-- The node under screen point (x, y): its tree row's, else the shape or
-- path drawn there, else the model's;
-- and whether the point is on the builder column or top bar.
local function nodeAt(screen, x, y)
	if y < screen.scfg.topBarHeight then
		return nil, true
	end
	if screen.scene and BuilderColumn.contains(ScriptBuilderScreen.column(screen), x, y) then
		local row = TreePanel.rowAt(ScriptBuilderScreen.treeRows(screen), x, y)
		if row then
			return row.owner or row.node.id, true
		end
		return nil, true
	end
	if screen.scene then
		local outline = outlineAt(screen, x, y, true)
		if outline then
			return outline, false
		end
	end
	return pickAt(screen, x, y), false
end

local function ctrlDown()
	return love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
		or love.keyboard.isDown("lgui") or love.keyboard.isDown("rgui")
end

local function shiftDown()
	return love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
end

-- The code panel's layout (CodePanel.layout), or nil when it is put away.
function ScriptBuilderScreen.codePanel(screen)
	local code = screen.code
	if not (code and code.open) then
		return nil
	end
	return CodePanel.layout(ScriptBuilderScreen.viewport(screen), #code.buffer.lines)
end

-- Shows the code panel: on the script's text as it stands, unless it
-- still holds the same script's text from before (unrun edits kept).
local function openCode(screen)
	local shown = text(screen) or ""
	local code = screen.code
	if not code or code.shown ~= shown then
		code = { buffer = TextBuffer.new(shown), scroll = 0, base = shown, shown = shown }
		code.errorLine = screen.message and Sandbox.errorLine(screen.message, screen.chunk)
		screen.code = code
	end
	code.open, code.openedAt, code.dragging = true, screen.clock, nil
end

-- Scrolls the code panel just enough to show the cursor.
local function followCursor(screen)
	local code = screen.code
	code.scroll = CodePanel.scroll(ScriptBuilderScreen.codePanel(screen), code.buffer, code.scroll)
end

-- Runs the code panel's text as the script (Ctrl+Enter): checked like a
-- file read (Lockcheck), it becomes the scene -- editable when
-- declarative, else locked -- with a fresh undo history, and the model
-- rebuilds. A script that fails keeps the model as it was and marks the
-- line its error points at. True when it ran.
function ScriptBuilderScreen.runCode(screen)
	local code = screen.code
	local source = TextBuffer.text(code.buffer)
	local checked, reason = Lockcheck.check(source, screen.chunk)
	if not checked then
		code.errorLine = Sandbox.errorLine(reason, screen.chunk)
		screen.message = reason
		return false
	end
	screen.source = source
	screen.scene, screen.locked, screen.history = Scene.new(checked.root), checked.locked, History.new()
	rebuild(screen)
	code.errorLine = screen.message and Sandbox.errorLine(screen.message, screen.chunk)
	code.base, code.shown = source, text(screen)
	return true
end

-- Open folder: the folder the open script saves in, opened for an
-- external editor where the system allows, its path in the status either
-- way.
local function openFolder(screen)
	local cfg = screen.config.designs
	local path = love.filesystem.getSaveDirectory() .. "/" .. (screen.kind == "prefabs" and cfg.prefabDir or cfg.dir)
	if love.system.openURL("file://" .. path) then
		screen.status = "Opened " .. path
	else
		screen.status = "Can't open the folder: it is " .. path
	end
end

-- A left press on code panel part `part` (CodePanel.hit) at (x, y).
local function codeClick(screen, part, x, y)
	local code = screen.code
	if part == "run" then
		ScriptBuilderScreen.runCode(screen)
	elseif part == "folder" then
		openFolder(screen)
	elseif part == "text" then
		local line, col = CodePanel.position(ScriptBuilderScreen.codePanel(screen), code.buffer, code.scroll, x, y)
		TextBuffer.place(code.buffer, line, col, shiftDown())
		code.dragging = true
	end
end

-- The keys the code panel moves its cursor by.
local CODE_MOVES = { left = "left", right = "right", up = "up", down = "down", home = "home", ["end"] = "end" }

-- Keys while the code panel is showing: they edit its text. Ctrl+Enter
-- runs it, Ctrl+C/X/V copy, cut and paste, Ctrl+A selects all, Ctrl+S
-- runs and saves; Esc puts the panel away, its text kept.
local function codeKey(screen, key)
	local code = screen.code
	local buf = code.buffer
	if ctrlDown() then
		if key == "return" or key == "kpenter" then
			ScriptBuilderScreen.runCode(screen)
		elseif key == "c" or key == "x" then
			local selected = key == "c" and TextBuffer.selected(buf) or TextBuffer.cut(buf)
			if selected then
				love.system.setClipboardText(selected)
			end
		elseif key == "v" then
			TextBuffer.insert(buf, love.system.getClipboardText() or "")
		elseif key == "a" then
			TextBuffer.selectAll(buf)
		elseif key == "s" then
			save(screen)
		end
	elseif key == "escape" then
		code.open, screen.tool = false, "select"
		return
	elseif key == "return" or key == "kpenter" then
		TextBuffer.insert(buf, "\n")
	elseif key == "tab" then
		TextBuffer.insert(buf, "\t")
	elseif key == "backspace" then
		TextBuffer.backspace(buf)
	elseif key == "delete" then
		TextBuffer.delete(buf)
	elseif CODE_MOVES[key] then
		TextBuffer.move(buf, CODE_MOVES[key], shiftDown())
	end
	followCursor(screen)
end

local function select(screen, id, add)
	if screen.scene then
		Scene.select(screen.scene, id, add)
		screen.revision = screen.revision + 1
	end
end

-- `slot` moved to sit just right of the builder column, so a tool's menu
-- hangs beside the column and never covers its sections.
local function besideColumn(slot)
	local moved = {}
	for k, v in pairs(slot) do
		moved[k] = v
	end
	moved.x = BuilderColumn.MARGIN + BuilderColumn.WIDTH + 16
	return moved
end

-- The Insert tool's menu rows (InsertMenu.rows) under its top bar slot,
-- or nil when the tool is off.
function ScriptBuilderScreen.insertMenu(screen)
	if not (screen.insert and screen.insert.menuOpen) then
		return nil
	end
	for _, slot in ipairs(ScriptBuilderScreen.topBar(screen)) do
		if slot.tool and slot.tool.id == "insert" then
			return InsertMenu.rows(screen.insert.items, besideColumn(slot))
		end
	end
end

-- The material panel's rows (MaterialPanel.rows) in the column's Material
-- section, or nil when the selection has no volume or the section is
-- collapsed.
function ScriptBuilderScreen.materialPanel(screen)
	local content = paintShown(screen) and sectionContent(ScriptBuilderScreen.column(screen), "material")
	if not content then
		return nil
	end
	return MaterialPanel.rows(shownMaterial(screen), screen.config.materials, content)
end

-- The Properties section's fields (PropertiesStrip.fields) for the one
-- selected node; none unless one editable primitive is selected, or when
-- the section is collapsed.
function ScriptBuilderScreen.properties(screen)
	local content = sectionContent(ScriptBuilderScreen.column(screen), "properties")
	if not content then
		return {}
	end
	return PropertiesStrip.fields(shownProperties(screen), content.x, content.y, content.width)
end

-- The Params section's rows (ParamsPanel.rows), one per param shown; none
-- when the section is collapsed.
function ScriptBuilderScreen.paramsPanel(screen)
	local content = sectionContent(ScriptBuilderScreen.column(screen), "params")
	if not content then
		return {}
	end
	return ParamsPanel.rows((shownParams(screen)), content.x, content.y, content.width)
end

-- The colour picker's layout (ColourPicker.layout) in the column's Colour
-- section, or nil when the selection has no volume or it is collapsed.
function ScriptBuilderScreen.colourPicker(screen)
	local content = paintShown(screen) and sectionContent(ScriptBuilderScreen.column(screen), "colour")
	if not content then
		return nil
	end
	return ColourPicker.layout(ColourPicker.builderSections(screen.recentColours), content.x, content.y)
end

-- A click on colour picker swatch `swatch`: the selection painted its
-- colour, one undo step, and the colour first in the recent row.
local function colourClick(screen, swatch)
	if #screen.scene.selection == 0 then
		screen.message = "Select the nodes to colour"
		return
	end
	RecentColours.add(screen.recentColours, swatch.color)
	edit(screen, Scene.setColor, swatch.color)
end

-- The library manager's layout (LibraryPanel.layout) down the right edge
-- under the top bar, or nil when it is shut.
function ScriptBuilderScreen.libraryPanel(screen)
	local open = screen.libraryOpen
	if not open then
		open = screen.insert and screen.insert.picker
		if not open then
			return nil
		end
		return LibraryPanel.layout(open.entries, "pick", ScriptBuilderScreen.viewport(screen), open.scroll)
	end
	return LibraryPanel.layout(open.entries, open.tab, ScriptBuilderScreen.viewport(screen), open.scroll)
end

-- The state the panel shows: the manager's, or the Insert prefab picker's.
local function panelState(screen)
	return screen.libraryOpen or (screen.insert and screen.insert.picker)
end

-- Rereads the design library and lists tab `tab` of the manager (the one
-- showing unless given), each row with the blueprint its script compiles
-- to for a thumbnail; nothing armed.
local function listLibrary(screen, tab)
	screen.lib = screen.library()
	local previous = screen.libraryOpen
	tab = tab or previous.tab
	local scroll = previous and previous.tab == tab and previous.scroll or 0
	local entries = Library.entries(screen.lib, tab)
	for _, entry in ipairs(entries) do
		entry.blueprint = Compile.design(screen.lib[tab][entry.name], entry.name, screen.lib, screen.config)
	end
	screen.libraryOpen = { tab = tab, entries = entries, scroll = scroll }
end

-- Lists every prefab, with thumbnails, in the Insert tool's picker (opens
-- it, or refreshes it keeping its scroll).
local function listPicker(screen)
	screen.lib = screen.library()
	local entries = Library.entries(screen.lib, "prefabs")
	for _, entry in ipairs(entries) do
		entry.blueprint = Compile.design(screen.lib.prefabs[entry.name], entry.name, screen.lib, screen.config)
	end
	local previous = screen.insert.picker
	screen.insert.picker = { entries = entries, scroll = previous and previous.scroll or 0 }
end

-- Runs `go` (which opens another script) now, or after the unsaved-changes
-- prompt when the open script has changes not saved.
local function switch(screen, go)
	if ScriptBuilderScreen.dirty(screen) then
		screen.unsaved = { go = go }
		return
	end
	go()
end

-- What New starts: an empty design named "untitled", else the first free
-- of "untitled2", "untitled3", ... (Library.freeName), not saved until
-- Ctrl+S.
local NEW_NAME = "untitled"
local EMPTY_DESIGN = "return group{}\n"

-- What each library manager button does to script `name` of `kind`.
local LIBRARY_ACTIONS = {
	open = function(screen, kind, name)
		switch(screen, function()
			openScript(screen, kind, name)
		end)
	end,
	duplicate = function(screen, kind, name)
		local to = Library.copyName(screen.lib, kind, name)
		local ok, why = Library.duplicate(screen.lib, kind, name, to)
		if ok then
			ok, why = DesignStore.write(screen.config.designs, kind, to, screen.lib[kind][name])
		end
		if not ok then
			screen.message = why
			return
		end
		listLibrary(screen)
		screen.status = "Duplicated " .. name .. " as " .. to
	end,
	rename = function(screen, kind, name)
		local ok, why = Library.removable(kind, name)
		if not ok then
			screen.message = why
			return
		end
		screen.libraryRename = { kind = kind, name = name, text = name }
	end,
	delete = function(screen, kind, name)
		local ok, why = Library.delete(screen.lib, kind, name)
		if ok then
			ok, why = DesignStore.remove(screen.config.designs, kind, name)
		end
		if not ok then
			screen.message = why
			return
		end
		if screen.kind == kind and screen.name == name then
			-- Only the builder holds it now: it counts as unsaved.
			screen.saved = nil
		end
		listLibrary(screen)
		screen.status = "Deleted " .. name
	end,
	reset = function(screen, kind, name)
		local cfg = screen.config.designs
		local ok, why = Library.reset(DesignStore.load(cfg), kind, name)
		if not ok then
			screen.message = why
			return
		end
		local function go()
			local removed, err = DesignStore.remove(cfg, kind, name)
			if not removed then
				screen.message = err
				return
			end
			if screen.kind == kind and screen.name == name then
				openScript(screen, kind, name)
			end
			if screen.libraryOpen then
				listLibrary(screen)
			end
			if screen.insert and screen.insert.picker then
				listPicker(screen)
			end
			screen.status = "Reset " .. name .. " to default"
		end
		if screen.kind == kind and screen.name == name then
			switch(screen, go)
		else
			go()
		end
	end,
}

-- Renames the script the manager's Rename prompt is on to the name typed:
-- its file moves, and nothing that places it by its old name changes. The
-- open script keeps its edits under the new name.
local function commitLibraryRename(screen)
	local r = screen.libraryRename
	screen.libraryRename = nil
	if r.text == r.name then
		return
	end
	local ok, why = Library.rename(screen.lib, r.kind, r.name, r.text)
	if ok then
		ok, why = DesignStore.rename(screen.config.designs, r.kind, r.name, r.text)
	end
	if not ok then
		screen.message = why
		return
	end
	if screen.kind == r.kind and screen.name == r.name then
		screen.name, screen.chunk = r.text, r.text
	end
	listLibrary(screen)
	screen.status = "Renamed " .. r.name .. " to " .. r.text
end

-- A click on what `hit` (LibraryPanel.hit) names. A Delete needs a second
-- click; any other click disarms it.
local function libraryClick(screen, hit)
	local open = screen.libraryOpen
	local armed = open.armed
	open.armed = nil
	if hit.tab then
		listLibrary(screen, hit.tab)
	elseif hit.new then
		switch(screen, function()
			screen.lib = screen.library()
			openScript(screen, "designs", Library.freeName(screen.lib, "designs", NEW_NAME), nil, EMPTY_DESIGN)
		end)
	elseif hit.action == "delete" and armed ~= hit.row.entry.name then
		open.armed = hit.row.entry.name
		screen.message = "Click Confirm to delete " .. hit.row.entry.name
	else
		LIBRARY_ACTIONS[hit.action](screen, open.tab, hit.row.entry.name)
	end
end

-- The open material dropdown's layout (Dropdown.layout) with its row, or
-- nil when none is open; one open for a selection that has since changed
-- or a section that is gone closes.
function ScriptBuilderScreen.dropdown(screen)
	local d = screen.dropdown
	if not d then
		return nil
	end
	local rows = screen.scene and ScriptBuilderScreen.materialPanel(screen)
	for _, row in ipairs(rows or {}) do
		if row.kind == d.kind and screen.scene.selection[1] == d.id then
			local _, h = Screen.dimensions()
			return Dropdown.layout(MaterialPanel.box(row), row.options, true, h), row
		end
	end
	screen.dropdown = nil
	return nil
end

-- A click on the material panel's `row` (stepper box `part`): the
-- selection made of the material it picks, one undo step.
local function materialClick(screen, row, part)
	local material = MaterialPanel.choose(shownMaterial(screen), screen.config.materials, row, part)
	if not material then
		return
	end
	if #screen.scene.selection == 0 then
		screen.message = "Select the nodes to make of a material"
		return
	end
	edit(screen, Scene.setMaterial, material)
end

-- Sets the param at `index` to `value`, clamped: a selected instance's
-- override (Scene.setParam, one undo step), else its default rewritten in
-- the script's text; the design rebuilt. A bad value is refused with why.
local function setParam(screen, index, value)
	local params, instance = shownParams(screen)
	local param = params[index]
	local clamped, why = Params.clamp(param, value)
	if clamped == nil then
		screen.message = param.label .. " " .. why
		return
	end
	if not param.name then
		screen.message = param.label .. " is not declared at the top level, so edit it as text"
		return
	end
	if instance then
		edit(screen, Scene.setParam, instance.id, param.name, clamped)
		return
	end
	local rewritten, problem = Params.rewrite(screen.source, param.name, clamped)
	if not rewritten then
		screen.message = problem
		return
	end
	screen.source = rewritten
	rebuild(screen)
end

-- The next of choice param `param`'s options, round to the first.
local function nextOption(param)
	for i, option in ipairs(param.options) do
		if option == param.value then
			return param.options[i % #param.options + 1]
		end
	end
	return param.options[1]
end

-- A click on `part` of params panel row `row`.
local function paramClick(screen, row, part)
	local param = row.param
	if part == "minus" or part == "plus" then
		setParam(screen, row.index, Params.step(param, part == "plus" and 1 or -1))
	elseif param.kind == "bool" then
		setParam(screen, row.index, not param.value)
	elseif param.kind == "choice" then
		setParam(screen, row.index, nextOption(param))
	else
		local shown = param.kind == "color" and table.concat(param.value, " ") or tostring(param.value)
		screen.paramField = { index = row.index, text = shown, initial = shown }
	end
end

-- Sets the param the panel's text box is on to what was typed: a number,
-- or a colour's three numbers. Unchanged text does nothing.
local function commitParamField(screen)
	local f = screen.paramField
	screen.paramField = nil
	if f.text == f.initial then
		return
	end
	local param = shownParams(screen)[f.index]
	local value = tonumber(f.text)
	if param.kind == "color" then
		value = {}
		for n in f.text:gmatch("[^%s,]+") do
			value[#value + 1] = tonumber(n)
		end
	end
	setParam(screen, f.index, value)
end

-- The middle of the selection's geometry in the blueprint's space
-- (Transform.centre), or nil; worked out once per revision.
local function selectionCentre(screen)
	if not screen.scene then
		return nil
	end
	local cached = screen.centreCache
	if not cached or cached.revision ~= screen.revision then
		cached = { revision = screen.revision, centre = Transform.centre(screen.scene, screen.targets) }
		screen.centreCache = cached
	end
	return cached.centre
end

-- The ray through screen point (x, y) in the design's own space, in tiles:
-- through the view a running transform began with, else this frame's.
local function designRay(screen, x, y)
	local t = screen.transform
	local origin = t and t.origin or screen.origin
	local o, d = BuilderCamera.ray(t and t.view or ScriptBuilderScreen.view(screen), x, y)
	local s = screen.cfg.studsPerTile
	return { o[1] / s + origin[1], o[2] / s + origin[2], o[3] / s }, d
end

-- Where screen point (x, y) meets `plane` (the work plane unless given):
-- its plane coordinates { a, b } and design-space point, snapped unless
-- Shift is held; nil when the pointer is off it.
local function planeHit(screen, x, y, plane)
	local o, d = designRay(screen, x, y)
	return WorkPlane.hit(plane or screen.plane, o, d, shiftDown())
end

-- The point on the work plane under screen point (x, y), in design space
-- (tiles), snapped unless Shift is held; nil when the pointer is off it.
local function workPoint(screen, x, y)
	local _, point = planeHit(screen, x, y)
	return point
end

-- Whether screen point (x, y) is within reach of design-space point p.
local function near(screen, x, y, p)
	local sx, sy = WorkPlaneView.pixel(ScriptBuilderScreen.view(screen), screen.cfg.studsPerTile, screen.origin, p)
	return sx ~= nil and (sx - x) ^ 2 + (sy - y) ^ 2 <= POINT_REACH * POINT_REACH
end

-- Places the Insert tool's armed item on the work plane under screen
-- point (x, y), as one undo step, and goes back to Select with it
-- selected.
local function place(screen, x, y)
	local armed = screen.insert.armed
	if not armed then
		screen.message = "Pick something to insert"
		return
	end
	local point = workPoint(screen, x, y)
	if not point then
		return
	end
	screen.insert, screen.tool = nil, "select"
	edit(screen, Scene.insert, Insert.node(armed, point))
end

-- The Draw tool's menu rows (InsertMenu.rows) under its top bar slot: the
-- kinds it draws under their headers; nil when the tool is off or the menu
-- closed by a pick.
function ScriptBuilderScreen.shapeMenu(screen)
	if not (screen.shape and screen.shape.menuOpen) then
		return nil
	end
	for _, slot in ipairs(ScriptBuilderScreen.topBar(screen)) do
		if slot.tool and slot.tool.id == screen.tool then
			return InsertMenu.rows(screen.shape.kinds, besideColumn(slot))
		end
	end
end

-- Makes axis plane `name` at the current height, or the ground, the work
-- plane.
local function setPlane(screen, name)
	screen.planeName = name
	screen.plane = name == "Ground" and WorkPlane.ground() or WorkPlane.axis(name, screen.planeHeight)
	if screen.shape then
		screen.shape.drawing = nil
	end
end

-- Moves the axis work plane one quarter tile up (dir 1) or down (-1); the
-- ground and a face stay.
local function stepPlane(screen, dir)
	local name = screen.planeName
	if name == "XY" or name == "XZ" or name == "YZ" then
		screen.planeHeight = screen.planeHeight + dir * WorkPlane.SNAP
		setPlane(screen, name)
	end
end

-- Adopts the model's face under screen point (x, y) as the work plane;
-- nothing there leaves the plane as it was.
local function adoptFace(screen, x, y)
	local tool = screen.shape or screen.insert
	tool.picking = nil
	local origin, direction = BuilderCamera.ray(ScriptBuilderScreen.view(screen), x, y)
	local s, o = screen.cfg.studsPerTile, screen.origin
	local at = { origin[1] / s, origin[2] / s, origin[3] / s }
	local id, t, normal = Pick.at(screen.targets, at, direction)
	if not id then
		screen.message = "No face there"
		return
	end
	local point = { at[1] + direction[1] * t + o[1], at[2] + direction[2] * t + o[2], at[3] + direction[3] * t }
	screen.plane, screen.planeName = WorkPlane.face(point, normal), "Face"
	screen.message = nil
end

-- Closes the outline under way into a shape node, one undo step, selected;
-- a bad outline is refused with why and stays open.
local function closeShape(screen, points)
	local node, why = ShapeTool.node(points, screen.plane)
	if not node then
		screen.message = "Can't close the shape: " .. why
		return
	end
	screen.shape.drawing = nil
	edit(screen, Scene.insert, node)
end

-- Makes the path under way a path node, one undo step, selected; clicks
-- that make none are refused with why and stay.
local function finishPath(screen)
	local tool = screen.shape
	local node, why = PathTool.node(tool.kind.curve, tool.drawing.points, screen.plane)
	if not node then
		screen.message = "Can't make the path: " .. why
		return
	end
	tool.drawing = nil
	edit(screen, Scene.insert, node)
end

-- A click with the Path tool at plane point `at`, screen point (x, y).
local function pathClick(screen, at, x, y)
	local tool = screen.shape
	local curve = tool.kind.curve
	local drawing = tool.drawing or { points = {} }
	tool.drawing = drawing
	local points = drawing.points
	local last = points[#points]
	if not PathTool.CLICKS[curve] and #points >= 2 and near(screen, x, y, WorkPlane.at(screen.plane, last[1], last[2])) then
		finishPath(screen)
		return
	end
	points[#points + 1] = { at[1], at[2] }
	if curve == "bezier" then
		drawing.dragging = #points
	end
	if #points == PathTool.CLICKS[curve] then
		finishPath(screen)
	end
end

-- Whether this press at screen point (x, y) is the second of a
-- double-click while drawing points; every press is remembered.
local function doubleClicked(screen, x, y)
	local last = screen.lastDraw
	screen.lastDraw = { x = x, y = y, time = screen.clock }
	return last ~= nil
		and screen.clock - last.time <= DOUBLE_CLICK
		and (last.x - x) ^ 2 + (last.y - y) ^ 2 <= POINT_REACH * POINT_REACH
end

-- A double-click's finish: the first press already added its point (or
-- finished the drawing, leaving nothing to do); one repeating the point
-- before it is dropped, then a polygon or freeform outline closes and a
-- path finishes.
local function finishDrawing(screen)
	local tool = screen.shape
	local drawing = tool.drawing
	if not drawing or drawing.anchor then
		return
	end
	local points = drawing.points
	local last, before = points[#points], points[#points - 1]
	if before and last[1] == before[1] and last[2] == before[2] then
		points[#points] = nil
	end
	drawing.dragging = nil
	if tool.path then
		finishPath(screen)
	else
		closeShape(screen, points)
	end
end

-- A click with the Shape or Path tool at screen point (x, y) in the view.
local function shapeClick(screen, x, y)
	local tool = screen.shape
	if not tool.picking and doubleClicked(screen, x, y) and (tool.path or (tool.kind.kind ~= "rect" and tool.kind.kind ~= "ellipse")) then
		finishDrawing(screen)
		return
	end
	if tool.picking then
		adoptFace(screen, x, y)
		return
	end
	if tool.path then
		local at = planeHit(screen, x, y)
		if at then
			pathClick(screen, at, x, y)
		end
		return
	end
	local at = planeHit(screen, x, y)
	if not at then
		return
	end
	local kind = tool.kind.kind
	local drawing = tool.drawing
	if kind == "rect" or kind == "ellipse" then
		if not drawing then
			tool.drawing = { anchor = at, points = {} }
		else
			closeShape(screen, Shape2d[kind](drawing.anchor, at))
			tool.drawing = nil
		end
		return
	end
	drawing = drawing or { points = {} }
	tool.drawing = drawing
	local first = drawing.points[1]
	if first and #drawing.points >= 3 and near(screen, x, y, WorkPlane.at(screen.plane, first[1], first[2])) then
		closeShape(screen, drawing.points)
		return
	end
	drawing.points[#drawing.points + 1] = { at[1], at[2] }
	if kind == "path" then
		drawing.dragging = #drawing.points
	end
end

-- The held button dragging the handle of the path point just placed out
-- to plane point `at`: a handle of any length makes it smooth.
local function dragHandle(drawing, at)
	local p = drawing.points[drawing.dragging]
	local hx, hy = at[1] - p[1], at[2] - p[2]
	if hx == 0 and hy == 0 then
		p[3], p[4] = nil, nil
	else
		p[3], p[4] = hx, hy
	end
end

-- The selected shape (WorkPlane.shapes) whose points can be dragged, or
-- nil: exactly one editable shape selected.
local function selectedShape(screen)
	local scene = screen.scene
	if screen.locked or not scene or #scene.selection ~= 1 then
		return nil
	end
	for _, s in ipairs(WorkPlane.shapes(scene.root)) do
		if s.id == scene.selection[1] then
			return s
		end
	end
end

-- The point of the selected shape within reach of screen point (x, y):
-- its shape (WorkPlane.shapes) and index, or nil.
local function shapePointAt(screen, x, y)
	local s = selectedShape(screen)
	if not s then
		return nil
	end
	for i, p in ipairs(s.node.points) do
		if near(screen, x, y, WorkPlane.at(s.plane, p[1], p[2])) then
			return s, i
		end
	end
end

-- Shows the dragged point at screen point (x, y), on its shape's plane;
-- a spot that would spoil the outline leaves it where it was.
local function followPoint(screen, x, y)
	local d = screen.pointDrag
	local at = planeHit(screen, x, y, d.plane)
	if not at then
		return
	end
	local scene = { root = Scene.copy(d.before), selection = screen.scene.selection }
	if ShapeTool.movePoint(scene, d.id, d.index, at[1], at[2]) then
		d.at = at
		screen.scene.root = scene.root
		rebuild(screen)
	end
end

-- Ends the point drag: the move kept as one undo step when it went
-- anywhere.
local function endPointDrag(screen)
	local d = screen.pointDrag
	screen.pointDrag = nil
	screen.scene.root = d.before
	if d.at then
		edit(screen, ShapeTool.movePoint, d.id, d.index, d.at[1], d.at[2])
	else
		rebuild(screen)
	end
end

-- The corners of the outline under way, in design space: a rect or
-- ellipse from its first corner to the pointer, a polygon or path through
-- its points and on to the pointer, left open; and whether it is closed.
local function drawingCorners(screen)
	local tool = screen.shape
	local drawing = tool and tool.drawing
	if not drawing then
		return nil
	end
	local points = {}
	if tool.path then
		for i, p in ipairs(drawing.points) do
			points[i] = p
		end
		if screen.hover and not drawing.dragging then
			points[#points + 1] = screen.hover
		end
		local node = PathTool.node(tool.kind.curve, points, screen.plane)
		if node then
			return Path.points(node), false
		end
		local corners = {}
		for i, p in ipairs(points) do
			corners[i] = WorkPlane.at(screen.plane, p[1], p[2])
		end
		return corners, false
	end
	if drawing.anchor then
		if not screen.hover then
			return nil
		end
		points = Shape2d[tool.kind.kind](drawing.anchor, screen.hover)
	else
		for i, p in ipairs(drawing.points) do
			points[i] = p
		end
		if screen.hover and not drawing.dragging then
			points[#points + 1] = screen.hover
		end
	end
	local corners = {}
	for i, p in ipairs(Shape2d.trace(points, not drawing.anchor)) do
		corners[i] = WorkPlane.at(screen.plane, p[1], p[2])
	end
	return corners, drawing.anchor ~= nil
end

-- The line of help while the Shape or Path tool is on, by what it draws;
-- nil when neither is.
function ScriptBuilderScreen.hint(screen)
	local tool = screen.shape
	if not tool then
		return nil
	end
	if tool.picking then
		return "Click a face to draw on · Esc to cancel"
	end
	if tool.path then
		local clicks = PathTool.CLICKS[tool.kind.curve]
		if clicks then
			return "Click " .. clicks .. " points · Esc to cancel"
		end
		return "Click to add points · Enter or double-click to finish · Esc to cancel"
	end
	local kind = tool.kind.kind
	if kind == "rect" or kind == "ellipse" then
		return "Click two corners · Esc to cancel"
	end
	if kind == "path" then
		return "Click to add points, drag for curves · Enter or double-click to close · Esc to cancel"
	end
	return "Click to add points · Enter or double-click to close · Esc to cancel"
end

-- What the shape overlay (src/app/render/shape_overlay.lua) draws, in
-- design space: every shape's outline and every path (selected ones
-- marked), the selected shape's points and their handles, and the outline
-- or path under way.
function ScriptBuilderScreen.overlay(screen)
	local out = { outlines = {}, points = {}, hint = ScriptBuilderScreen.hint(screen) }
	if not screen.scene then
		return out
	end
	for _, s in ipairs(WorkPlane.shapes(screen.scene.root)) do
		out.outlines[#out.outlines + 1] = { corners = s.outline, closed = true, selected = Scene.isSelected(screen.scene, s.id), hovered = screen.hoverOutline == s.id }
	end
	for _, p in ipairs(WorkPlane.paths(screen.scene.root)) do
		out.outlines[#out.outlines + 1] = { corners = p.points, closed = false, selected = Scene.isSelected(screen.scene, p.id), hovered = screen.hoverOutline == p.id }
	end
	local s = selectedShape(screen)
	if s then
		for _, p in ipairs(s.node.points) do
			local point = { at = WorkPlane.at(s.plane, p[1], p[2]) }
			if p[3] then
				point.handles = {
					WorkPlane.at(s.plane, p[1] - p[3], p[2] - p[4]),
					WorkPlane.at(s.plane, p[1] + p[3], p[2] + p[4]),
				}
			end
			out.points[#out.points + 1] = point
		end
	end
	local corners, closed = drawingCorners(screen)
	if corners then
		out.drawing = { corners = corners, closed = closed }
		for i, p in ipairs(screen.shape.drawing.points) do
			local point = { at = WorkPlane.at(screen.plane, p[1], p[2]) }
			if i == 1 and not screen.shape.path and not screen.shape.drawing.anchor then
				local m = screen.mouse
				point.first, point.lit = true, m ~= nil and near(screen, m.x, m.y, point.at)
			end
			out.points[#out.points + 1] = point
		end
	end
	return out
end

-- Begins transform `mode` on the selection, held to `axis` (or nil), with
-- the pointer at (x, y), or on the selection's centre when not given.
-- `gizmo` when it is a handle drag.
local function startTransform(screen, mode, axis, x, y, gizmo)
	if screen.locked then
		screen.message = LOCKED_MESSAGE
		return
	end
	local centre = selectionCentre(screen)
	if not centre then
		screen.message = "Select something to " .. mode
		return
	end
	screen.gizmoMode = mode
	local view, s = ScriptBuilderScreen.view(screen), screen.cfg.studsPerTile
	if not x then
		x, y = BuilderCamera.project(view, centre[1] * s, centre[2] * s, centre[3] * s)
	end
	local o = screen.origin
	local t = { view = view, origin = { o[1], o[2] }, before = screen.scene.root, gizmo = gizmo, mouse = { x = x, y = y } }
	screen.transform = t
	t.drag = Transform.start(mode, { centre[1] + o[1], centre[2] + o[2], centre[3] }, designRay(screen, x, y))
	t.drag.axis = axis
	screen.message = nil
end

-- The running transform with the pointer at (x, y): the scene as it was,
-- transformed by how far the drag has gone, rebuilt.
local function follow(screen, x, y)
	local t = screen.transform
	t.mouse = { x = x, y = y }
	local o, d = designRay(screen, x, y)
	local amount = Transform.amount(t.drag, o, d, shiftDown())
	t.amount = amount or t.amount
	screen.scene.root = Scene.copy(t.before)
	if t.amount then
		Transform.apply(screen.scene, t.drag, t.amount)
	end
	rebuild(screen)
end

-- Whether `amount` of `drag` leaves everything where it was.
local function unchanged(drag, amount)
	if drag.mode == "move" then
		return amount[1] == 0 and amount[2] == 0 and amount[3] == 0
	end
	return amount == (drag.mode == "rotate" and 0 or 1)
end

-- Ends the running transform: kept as one undo step when `keep` and it
-- changed anything, else dropped.
local function endTransform(screen, keep)
	local t = screen.transform
	screen.transform = nil
	screen.scene.root = t.before
	if keep and t.amount and not unchanged(t.drag, t.amount) then
		edit(screen, Transform.apply, t.drag, t.amount)
	else
		rebuild(screen)
	end
end

-- Keys while a transform runs: axis keys hold it to that axis (again:
-- free it), Return keeps it, Esc drops it.
local function transformKey(screen, key)
	local t = screen.transform
	if key == "escape" then
		endTransform(screen, false)
	elseif key == "return" or key == "kpenter" then
		endTransform(screen, true)
	elseif AXIS_KEYS[key] then
		t.drag.axis = t.drag.axis ~= key and key or nil
		t.amount = nil
		follow(screen, t.mouse.x, t.mouse.y)
	end
end

-- The gizmo's handles (Gizmo.handles) on the selection, or nil when
-- nothing editable is selected.
function ScriptBuilderScreen.gizmo(screen)
	local centre = not screen.locked and selectionCentre(screen)
	if not centre then
		return nil
	end
	local mode = screen.transform and screen.transform.drag.mode or screen.gizmoMode
	return Gizmo.handles(ScriptBuilderScreen.view(screen), centre, screen.cfg.studsPerTile, mode)
end

-- Opens the rename box on node `id`, holding its label.
local function startRename(screen, id)
	if screen.locked then
		screen.message = LOCKED_MESSAGE
		return
	end
	local node = id and Scene.find(screen.scene, id)
	if node then
		screen.rename = { id = id, text = Scene.label(node) }
	end
end

local function commitRename(screen)
	local r = screen.rename
	screen.rename = nil
	local node = Scene.find(screen.scene, r.id)
	if node and r.text ~= Scene.label(node) then
		edit(screen, Scene.rename, r.id, r.text)
	end
end

-- Export as prefab with the name typed: the selection becomes one
-- instance of it (Scene.export, one undo step) and prefabs/<name>.lua is
-- written. A taken or bad name, or a failed write, changes nothing.
local function commitExport(screen)
	local name = screen.exportPrompt.text
	screen.exportPrompt = nil
	if not name:match("^[%w_%-]+$") then
		screen.message = "A prefab name is letters, digits, _ and -"
		return
	end
	if screen.lib.prefabs[name] then
		screen.message = "A prefab called " .. name .. " already exists"
		return
	end
	local ok, result = History.apply(screen.history, screen.scene, Scene.export, name, screen.lib)
	if not ok then
		rebuild(screen, result)
		return
	end
	local written, err = DesignStore.write(screen.config.designs, "prefabs", name, result)
	if not written then
		History.undo(screen.history, screen.scene)
		screen.history.future = {}
		rebuild(screen, "Export failed: " .. tostring(err))
		return
	end
	screen.lib = screen.library()
	screen.status = "Exported prefab " .. name
	rebuild(screen)
end

-- Picks top bar slot `slot`'s tool (defined below).
local setTool

local ACTIONS = {
	Rename = function(screen)
		startRename(screen, screen.scene.selection[1])
	end,
	Delete = function(screen)
		edit(screen, Scene.delete)
	end,
	Duplicate = function(screen)
		edit(screen, Scene.duplicate)
	end,
	Group = function(screen)
		edit(screen, Scene.group)
	end,
	Extrude = function(screen)
		edit(screen, Scene.extrude)
	end,
	Lathe = function(screen)
		edit(screen, Scene.lathe)
	end,
	-- Opens the name prompt; Return exports the selection (commitExport).
	["Export as prefab"] = function(screen)
		if screen.locked then
			screen.message = LOCKED_MESSAGE .. ": its nodes can't be exported"
		elseif #screen.scene.selection == 0 then
			screen.message = "Select the nodes to export as a prefab"
		else
			screen.exportPrompt = { text = "" }
		end
	end,
	Unlink = function(screen)
		edit(screen, Scene.unlink, screen.lib)
	end,
	-- Opens the one selected instance's prefab in the builder, after the
	-- unsaved-changes prompt if need be; a built-in saves as a shadow copy
	-- in the save directory.
	["Edit prefab"] = function(screen)
		local node = selectedInstance(screen)
		if not node then
			screen.message = "Select one prefab instance to edit its prefab"
			return
		end
		switch(screen, function()
			openScript(screen, "prefabs", node.prefab)
		end)
	end,
	-- Deletes the open built-in's shadow copy and shows the built-in again,
	-- after the unsaved-changes prompt if need be.
	["Reset to default"] = function(screen)
		LIBRARY_ACTIONS.reset(screen, screen.kind, screen.name)
	end,
	-- Waits for a click on the shape to sweep along the selected path.
	["Sweep a shape along this…"] = function(screen)
		local selection = screen.scene.selection
		local node = #selection == 1 and Scene.find(screen.scene, selection[1])
		if screen.locked then
			screen.message = LOCKED_MESSAGE
		elseif not node or node.kind ~= "path" then
			screen.message = "Select one path to sweep along"
		else
			screen.sweeping = { path = node.id }
			screen.message = "Click a shape to sweep along it (Esc drops it)"
		end
	end,
	-- Waits for a click on the path to sweep the selected shape along.
	["Sweep along path…"] = function(screen)
		local selection = screen.scene.selection
		local node = #selection == 1 and Scene.find(screen.scene, selection[1])
		if screen.locked then
			screen.message = LOCKED_MESSAGE
		elseif not node or node.kind ~= "shape" then
			screen.message = "Select one shape to sweep"
		else
			screen.sweeping = { id = node.id }
			screen.message = "Click a path to sweep along (Esc drops it)"
		end
	end,
}

-- The click after Sweep: the path under it (its tree row, or drawn in the
-- view) gets the shape swept along it, one undo step.
local function sweepClick(screen, x, y)
	local sweeping = screen.sweeping
	screen.sweeping = nil
	if sweeping.path then
		local id = nodeAt(screen, x, y)
		local node = id and Scene.find(screen.scene, id)
		if not node or node.kind ~= "shape" then
			screen.message = "No shape there to sweep"
			return
		end
		Scene.select(screen.scene, id, false)
		edit(screen, Scene.sweep, sweeping.path)
		return
	end
	local shape = sweeping.id
	local id, onPanel = nodeAt(screen, x, y)
	if not onPanel then
		id = pathAt(screen, x, y)
	end
	if not id then
		screen.message = "No path there to sweep along"
		return
	end
	Scene.select(screen.scene, shape, false)
	edit(screen, Scene.sweep, id)
end

function setTool(screen, slot)
	local tool = ScriptBuilderScreen.TOOLS[slot]
	if not tool then
		return
	end
	local again = screen.tool == tool.id
	screen.insert, screen.shape = nil, nil
	screen.libraryOpen = nil
	if screen.code then
		screen.code.open = false
	end
	if again then
		screen.tool = "select"
		return
	end
	if tool.id == "insert" or tool.id == "draw" then
		if not screen.scene then
			return
		elseif screen.locked then
			screen.message = LOCKED_MESSAGE
			return
		end
	end
	if tool.id == "insert" then
		screen.insert = { items = Insert.items(), menuOpen = true }
	elseif tool.id == "draw" then
		screen.shape = { kinds = DRAW_KINDS, kind = ShapeTool.KINDS[4], menuOpen = true }
	elseif tool.id == "library" then
		listLibrary(screen, screen.kind)
	elseif tool.id == "code" then
		openCode(screen)
	end
	screen.tool = tool.id
end

-- Opens the properties strip's text box on `field` (PropertiesStrip) of
-- the selected node, holding its value.
local function startField(screen, field)
	local text = tostring(field.prop.value)
	screen.field = { id = screen.scene.selection[1], key = field.prop.key, text = text, initial = text }
end

-- Sets the field's property to the number typed, one undo step, unless
-- the text is unchanged; a bad value is refused with why.
local function commitField(screen)
	local f = screen.field
	screen.field = nil
	if f.text ~= f.initial then
		edit(screen, Properties.set, f.id, f.key, tonumber(f.text))
	end
end

-- Runs the action labelled `item` (nil: nothing) for the menu or the
-- panel: Make 3D calls open(items) with its second level, Back calls back(),
-- any other label runs its handler.
local function runAction(screen, item, open, back)
	if item == Actions.MAKE_3D then
		local node = Scene.find(screen.scene, screen.scene.selection[1])
		open(Actions.make3d(node.kind))
	elseif item == Actions.BACK then
		back()
	elseif item then
		screen.panelSub = nil
		ACTIONS[item](screen)
	end
end

-- A left click at (x, y) outside any menu.
local function leftClick(screen, x, y)
	if screen.sweeping then
		sweepClick(screen, x, y)
		return
	end
	local open, openRow = ScriptBuilderScreen.dropdown(screen)
	if open then
		screen.dropdown = nil
		local kind, option = Dropdown.hit(open, x, y)
		if kind == "option" then
			materialClick(screen, { kind = openRow.kind, value = option.value })
		end
		return
	end
	local slot = TopBar.slotAt(ScriptBuilderScreen.topBar(screen), x, y)
	if slot then
		setTool(screen, slot.number)
		return
	end
	local codeLayout = ScriptBuilderScreen.codePanel(screen)
	if CodePanel.contains(codeLayout, x, y) then
		codeClick(screen, CodePanel.hit(codeLayout, x, y), x, y)
		return
	end
	local libraryLayout = ScriptBuilderScreen.libraryPanel(screen)
	local hit = LibraryPanel.hit(libraryLayout, x, y)
	if hit and hit.pick then
		screen.insert.armed = Insert.prefabItem(hit.row.entry.name)
		screen.insert.picker = nil
		return
	elseif hit then
		libraryClick(screen, hit)
		return
	elseif LibraryPanel.contains(libraryLayout, x, y) then
		if screen.libraryOpen then
			screen.libraryOpen.armed = nil
		end
		return
	elseif screen.libraryOpen then
		screen.libraryOpen.armed = nil
	end
	local menu = ScriptBuilderScreen.insertMenu(screen)
	local row = menu and InsertMenu.rowAt(menu, x, y)
	if row then
		screen.insert.menuOpen = false
		if row.item.pickPrefab then
			listPicker(screen)
		else
			screen.insert.armed = row.item
		end
		return
	end
	local shapeRows = ScriptBuilderScreen.shapeMenu(screen)
	local shapeRow = shapeRows and InsertMenu.rowAt(shapeRows, x, y)
	if shapeRow then
		local item = shapeRow.item
		if item.header then
			return
		end
		screen.shape.kind, screen.shape.drawing = item, nil
		screen.shape.path = item.curve ~= nil
		screen.shape.menuOpen = false
		return
	end
	if screen.scene then
		local col = ScriptBuilderScreen.column(screen)
		local hit = BuilderColumn.hit(col, x, y)
		if hit and hit.name == "plane" and hit.part == "content" then
			local pick = WorkPlaneSection.hit(ScriptBuilderScreen.workPlane(screen), x, y)
			local tool = screen.shape or screen.insert
			if pick and pick.step then
				stepPlane(screen, pick.step)
			elseif pick and pick.plane == "Face" then
				tool.picking = true
				if screen.shape then
					screen.shape.drawing = nil
				end
			elseif pick then
				tool.picking = nil
				setPlane(screen, pick.plane)
			end
			return
		end
		if hit and hit.part == "header" then
			screen.column.collapsed[hit.name] = not screen.column.collapsed[hit.name] or nil
			return
		elseif hit and hit.part == "thumb" then
			screen.column.dragging = { grab = y - col.bar.thumb.y }
			return
		elseif hit and hit.part == "track" then
			screen.column.dragging = { grab = col.bar.thumb.height / 2 }
			screen.column.scroll = BuilderColumn.dragScroll(col, screen.column.dragging.grab, y)
			return
		end
		if hit and hit.name == "params" then
			local paramRow, part = ParamsPanel.hit(ScriptBuilderScreen.paramsPanel(screen), x, y)
			if paramRow then
				paramClick(screen, paramRow, part)
			end
			return
		elseif hit and hit.name == "properties" then
			local field = PropertiesStrip.fieldAt(ScriptBuilderScreen.properties(screen), x, y)
			if field then
				startField(screen, field)
			end
			return
		end
		if hit and hit.name == "material" then
			local row, rowPart = MaterialPanel.hit(ScriptBuilderScreen.materialPanel(screen), x, y)
			if row and row.options then
				if #screen.scene.selection == 0 then
					screen.message = "Select the nodes to make of a material"
				else
					screen.dropdown = { kind = row.kind, id = screen.scene.selection[1] }
				end
			elseif row then
				materialClick(screen, row, rowPart)
			end
			return
		elseif hit and hit.name == "colour" then
			local swatch = ColourPicker.hit(ScriptBuilderScreen.colourPicker(screen), x, y)
			if swatch then
				colourClick(screen, swatch)
			end
			return
		end
		local panel = hit and hit.name == "actions" and ScriptBuilderScreen.actionPanel(screen)
		if panel then
			runAction(screen, ActionPanel.itemAt(panel, x, y), function(items)
				screen.panelSub = { items = items, id = screen.scene.selection[1] }
			end, function()
				screen.panelSub = nil
			end)
			return
		end
	end
	local id, onPanel = nodeAt(screen, x, y)
	if onPanel then
		if id then
			local last = screen.lastClick
			if last and last.id == id and screen.clock - last.time <= DOUBLE_CLICK then
				screen.lastClick = nil
				startRename(screen, id)
				return
			end
			screen.lastClick = { id = id, time = screen.clock }
			select(screen, id, ctrlDown())
		end
		return
	end
	if screen.insert then
		if screen.insert.picking then
			adoptFace(screen, x, y)
			return
		end
		place(screen, x, y)
		return
	end
	local grabbed, index = nil, nil
	if not (screen.shape and screen.shape.drawing) then
		grabbed, index = shapePointAt(screen, x, y)
	end
	if grabbed then
		screen.pointDrag = { id = grabbed.id, index = index, plane = grabbed.plane, before = screen.scene.root }
		return
	end
	if screen.shape then
		shapeClick(screen, x, y)
		return
	end
	local handles = ScriptBuilderScreen.gizmo(screen)
	local axis = handles and Gizmo.handleAt(handles, x, y)
	if axis then
		startTransform(screen, screen.gizmoMode, axis, x, y, true)
		return
	end
	if screen.tool == "select" then
		select(screen, id, ctrlDown())
	end
end

-- Whether design libraries a and b hold the same texts.
local function sameLibrary(a, b)
	for _, kind in ipairs({ "designs", "prefabs" }) do
		for _, pair in ipairs({ { a, b }, { b, a } }) do
			for name, source in pairs(pair[1][kind]) do
				if pair[2][kind][name] ~= source then
					return false
				end
			end
		end
	end
	return true
end

-- Hot reload: when the saved scripts' stamp (DesignStore.stamp) has
-- changed, rereads the library. The open script, changed on disk, opens
-- again as it now reads (locked or not by Lockcheck), the code panel too
-- if it was showing -- unless it has unsaved changes, which are kept, the
-- message saying the file changed. Any other change rebuilds the model,
-- since a prefab it places may be the one changed.
local function poll(screen)
	local stamp = DesignStore.stamp(screen.config.designs)
	if stamp == screen.stamp then
		return
	end
	screen.stamp = stamp
	local lib = screen.library()
	local disk = lib[screen.kind][screen.name]
	if disk == nil and screen.path then
		disk = screen.read(screen.path)
	end
	if disk ~= nil and disk ~= screen.diskText then
		screen.diskText = disk
		if ScriptBuilderScreen.dirty(screen) then
			screen.lib = lib
			rebuild(screen, screen.name .. " changed on disk: your unsaved edits are kept, Ctrl+S overwrites the file")
			return
		end
		local coding = screen.code and screen.code.open
		openScript(screen, screen.kind, screen.name, screen.path)
		if coding then
			openCode(screen)
			-- No key opened it: the next textinput is typed.
			screen.code.openedAt = nil
		end
		screen.status = "Reloaded " .. screen.name .. " from disk"
	elseif not sameLibrary(lib, screen.lib) then
		screen.lib = lib
		rebuild(screen)
		if screen.libraryOpen then
			listLibrary(screen)
		end
		if screen.insert and screen.insert.picker then
			listPicker(screen)
		end
	end
end

function ScriptBuilderScreen.update(screen, dt)
	screen.clock = screen.clock + dt
	-- Held keys repeat while the code panel is up, only then.
	local typing = screen.code ~= nil and screen.code.open
	if typing ~= (screen.keyRepeat or false) then
		love.keyboard.setKeyRepeat(typing)
		screen.keyRepeat = typing
	end
	screen.pollIn = (screen.pollIn or POLL) - dt
	if screen.pollIn <= 0 then
		screen.pollIn = POLL
		poll(screen)
	end
end

function ScriptBuilderScreen.mousepressed(screen, x, y, button)
	if screen.transform then
		if button == 2 or (button == 1 and not screen.transform.gizmo) then
			endTransform(screen, button == 1)
		end
		return
	end
	if button == 2 then
		screen.rightPress = { x = x, y = y, moved = 0 }
		return
	end
	if button ~= 1 then
		return
	end
	if screen.rename then
		commitRename(screen)
	end
	if screen.field then
		commitField(screen)
	end
	if screen.paramField then
		commitParamField(screen)
	end
	if screen.menu then
		local menu = screen.menu
		local item = ContextMenu.itemAt(menu, x, y)
		screen.menu = nil
		runAction(screen, item, function(items)
			screen.menu = ContextMenu.open(menu.x, menu.y, items)
			screen.menu.main = menu
		end, function()
			screen.menu = menu.main
		end)
		return
	end
	leftClick(screen, x, y)
end

-- A right-click without movement opens the context menu on the node under
-- the pointer, selecting it first unless it is selected already.
function ScriptBuilderScreen.mousereleased(screen, x, y, button)
	if button == 1 then
		screen.column.dragging = nil
	end
	if button == 1 and screen.code then
		screen.code.dragging = nil
	end
	if button == 1 and screen.transform and screen.transform.gizmo then
		endTransform(screen, true)
		return
	end
	if button == 1 and screen.pointDrag then
		endPointDrag(screen)
		return
	end
	if button == 1 and screen.shape and screen.shape.drawing then
		screen.shape.drawing.dragging = nil
	end
	if button ~= 2 or not screen.rightPress then
		return
	end
	local press = screen.rightPress
	screen.rightPress = nil
	if press.moved >= CLICK_SLOP or not screen.scene then
		return
	end
	if screen.rename then
		commitRename(screen)
	end
	local id = nodeAt(screen, x, y)
	if id and not Scene.isSelected(screen.scene, id) then
		select(screen, id, false)
	end
	screen.menu = ContextMenu.open(
		x, y, Actions.of(screen.scene, screen.scene.selection, screen.lib, screen.locked)
	)
end

function ScriptBuilderScreen.mousemoved(screen, x, y, dx, dy)
	screen.mouse = { x = x, y = y }
	screen.hover = (screen.shape or screen.insert) and planeHit(screen, x, y) or nil
	screen.hoverOutline = nil
	if screen.scene and not screen.shape and not screen.insert then
		local _, onPanel = nodeAt(screen, x, y)
		if not onPanel then
			screen.hoverOutline = outlineAt(screen, x, y, true)
		end
	end
	local drawing = screen.shape and screen.shape.drawing
	local code = screen.code
	if screen.column.dragging then
		screen.column.scroll = BuilderColumn.dragScroll(
			ScriptBuilderScreen.column(screen), screen.column.dragging.grab, y
		)
	elseif screen.transform then
		follow(screen, x, y)
	elseif code and code.open and code.dragging then
		local line, col = CodePanel.position(ScriptBuilderScreen.codePanel(screen), code.buffer, code.scroll, x, y)
		TextBuffer.place(code.buffer, line, col, true)
		followCursor(screen)
	elseif screen.pointDrag then
		followPoint(screen, x, y)
	elseif drawing and drawing.dragging and screen.hover then
		dragHandle(drawing, screen.hover)
	elseif screen.rightPress then
		screen.rightPress.moved = screen.rightPress.moved + math.abs(dx) + math.abs(dy)
		BuilderCamera.orbit(screen.camera, dx, dy, screen.cfg)
	end
end

function ScriptBuilderScreen.wheelmoved(screen, _, y)
	local libraryLayout = ScriptBuilderScreen.libraryPanel(screen)
	if screen.mouse and LibraryPanel.contains(libraryLayout, screen.mouse.x, screen.mouse.y) then
		panelState(screen).scroll = math.min(math.max(libraryLayout.scroll - WHEEL_STEP * y, 0), libraryLayout.maxScroll)
		return
	end
	local codeLayout, m = ScriptBuilderScreen.codePanel(screen), screen.mouse
	if m and CodePanel.contains(codeLayout, m.x, m.y) then
		screen.code.scroll = CodePanel.scroll(codeLayout, screen.code.buffer, screen.code.scroll, -3 * y)
		return
	end
	if m and screen.scene then
		local col = ScriptBuilderScreen.column(screen)
		if BuilderColumn.contains(col, m.x, m.y) then
			screen.column.scroll = BuilderColumn.clampScroll(col, col.scroll - WHEEL_STEP * y)
			return
		end
	end
	local _, radius = frame(screen)
	BuilderCamera.zoomAround(screen.camera, y, radius, screen.cfg)
end

-- Keys while the rename box is open: they edit its text.
local function renameKey(screen, key)
	if key == "backspace" then
		-- Drop the last UTF-8 character.
		screen.rename.text = screen.rename.text:gsub("[^\128-\191][\128-\191]*$", "")
	elseif key == "return" or key == "kpenter" then
		commitRename(screen)
	elseif key == "escape" then
		screen.rename = nil
	end
end

-- Keys while Export as prefab's name prompt is open: they edit its text.
local function exportKey(screen, key)
	if key == "backspace" then
		screen.exportPrompt.text = screen.exportPrompt.text:sub(1, -2)
	elseif key == "return" or key == "kpenter" then
		commitExport(screen)
	elseif key == "escape" then
		screen.exportPrompt = nil
	end
end

-- Keys while the library manager's Rename prompt is open: they edit its
-- text.
local function libraryRenameKey(screen, key)
	if key == "backspace" then
		screen.libraryRename.text = screen.libraryRename.text:sub(1, -2)
	elseif key == "return" or key == "kpenter" then
		commitLibraryRename(screen)
	elseif key == "escape" then
		screen.libraryRename = nil
	end
end

-- Keys while the unsaved-changes prompt is open: S saves then switches,
-- D drops the changes and switches, Esc stays.
local function unsavedKey(screen, key)
	local go = screen.unsaved.go
	if key == "s" then
		screen.unsaved = nil
		save(screen)
		if not ScriptBuilderScreen.dirty(screen) then
			go()
		end
	elseif key == "d" then
		screen.unsaved = nil
		go()
	elseif key == "escape" then
		screen.unsaved = nil
	end
end

-- Keys while the properties strip's text box is open: they edit its text.
local function fieldKey(screen, key)
	if key == "backspace" then
		screen.field.text = screen.field.text:sub(1, -2)
	elseif key == "return" or key == "kpenter" then
		commitField(screen)
	elseif key == "escape" then
		screen.field = nil
	end
end

-- Keys while the params panel's text box is open: they edit its text.
local function paramFieldKey(screen, key)
	if key == "backspace" then
		screen.paramField.text = screen.paramField.text:sub(1, -2)
	elseif key == "return" or key == "kpenter" then
		commitParamField(screen)
	elseif key == "escape" then
		screen.paramField = nil
	end
end

function ScriptBuilderScreen.keypressed(screen, key)
	if screen.transform then
		transformKey(screen, key)
	elseif screen.unsaved then
		unsavedKey(screen, key)
	elseif screen.libraryRename then
		libraryRenameKey(screen, key)
	elseif screen.rename then
		renameKey(screen, key)
	elseif screen.exportPrompt then
		exportKey(screen, key)
	elseif screen.field then
		fieldKey(screen, key)
	elseif screen.paramField then
		paramFieldKey(screen, key)
	elseif ScriptBuilderScreen.dropdown(screen) then
		if key == "escape" then
			screen.dropdown = nil
		end
	elseif screen.menu then
		if key == "escape" then
			screen.menu = nil
		end
	elseif screen.code and screen.code.open then
		codeKey(screen, key)
	elseif key == "escape" and screen.sweeping then
		screen.sweeping, screen.message = nil, nil
	elseif (key == "return" or key == "kpenter") and screen.shape and screen.shape.path and screen.shape.drawing then
		finishPath(screen)
	elseif (key == "return" or key == "kpenter") and screen.shape and screen.shape.drawing and not screen.shape.drawing.anchor then
		screen.shape.drawing.dragging = nil
		closeShape(screen, screen.shape.drawing.points)
	elseif key == "escape" and screen.libraryOpen then
		screen.libraryOpen, screen.tool = nil, "select"
	elseif key == "escape" and screen.insert then
		screen.insert, screen.tool = nil, "select"
	elseif key == "escape" and screen.shape and (screen.shape.drawing or screen.shape.picking) then
		screen.shape.drawing, screen.shape.picking = nil, nil
	elseif key == "escape" and screen.shape then
		screen.shape, screen.tool = nil, "select"
	elseif (key == "[" or key == "]") and screen.shape then
		stepPlane(screen, key == "]" and 1 or -1)
	elseif ctrlDown() then
		if key == "s" then
			save(screen)
		elseif key == "z" then
			undo(screen, shiftDown() and History.redo or History.undo)
		elseif key == "y" then
			undo(screen, History.redo)
		end
	elseif key:match("^%d$") then
		setTool(screen, tonumber(key))
	elseif TRANSFORM_KEYS[key] then
		local m = screen.mouse
		startTransform(screen, TRANSFORM_KEYS[key], nil, m and m.x, m and m.y, false)
	end
end

-- Typed text goes to the rename box, the properties strip's text box or
-- the params panel's.
function ScriptBuilderScreen.textinput(screen, typed)
	if screen.unsaved then
		return
	elseif screen.libraryRename then
		screen.libraryRename.text = screen.libraryRename.text .. typed
	elseif screen.rename then
		screen.rename.text = screen.rename.text .. typed
	elseif screen.exportPrompt then
		screen.exportPrompt.text = screen.exportPrompt.text .. typed
	elseif screen.field then
		screen.field.text = screen.field.text .. typed
	elseif screen.paramField then
		screen.paramField.text = screen.paramField.text .. typed
	elseif screen.code and screen.code.open and screen.clock ~= screen.code.openedAt then
		TextBuffer.insert(screen.code.buffer, typed)
		followCursor(screen)
	end
end

-- A one-line text box across the top of the view, holding `line`.
local function drawPrompt(line)
	local w = Screen.dimensions()
	local h = love.graphics.getFont():getHeight() + 12
	love.graphics.push("all")
	love.graphics.setColor(0.1, 0.1, 0.12, 0.95)
	love.graphics.rectangle("fill", w / 2 - 220, 60, 440, h, 4, 4)
	love.graphics.setColor(0.3, 0.5, 0.85, 1)
	love.graphics.rectangle("line", w / 2 - 220, 60, 440, h, 4, 4)
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.print(line, w / 2 - 212, 66)
	love.graphics.pop()
end

-- Draws `blueprint`'s sprite (facing N, bake scale 1, as the building
-- picker does) fitted into `rect`.
local function drawThumbnail(screen, blueprint, rect, palette)
	local sprite = BuildingsRender.sprite(screen.config, blueprint, "N", 1, nil, palette)
	local iw, ih = sprite.image:getDimensions()
	local scale = math.min(rect.width / iw, rect.height / ih)
	love.graphics.push("all")
	-- Premultiplied, like every baked sprite.
	love.graphics.setBlendMode("alpha", "premultiplied")
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.draw(sprite.image, rect.x + (rect.width - iw * scale) / 2, rect.y + (rect.height - ih * scale) / 2, 0, scale, scale)
	love.graphics.pop()
end

function ScriptBuilderScreen.draw(screen)
	local w = Screen.dimensions()
	local top = screen.scfg.topBarHeight
	local view = ScriptBuilderScreen.view(screen)
	ScriptBuilderView.draw(screen, view, function()
		WorkPlaneView.drawGround(view, screen.cfg.studsPerTile, screen.origin, WorkPlane.groundGrid(GROUND_EXTENT))
	end)
	if screen.shape or screen.insert then
		local lines = WorkPlane.grid(screen.plane, screen.hover or { 0, 0 }, GRID_EXTENT)
		WorkPlaneView.draw(view, screen.cfg.studsPerTile, screen.origin, lines)
	end
	ShapeOverlay.draw(view, screen.cfg.studsPerTile, screen.origin, ScriptBuilderScreen.overlay(screen))
	local handles = ScriptBuilderScreen.gizmo(screen)
	if handles then
		Gizmo.draw(handles, screen.transform and screen.transform.drag.axis)
	end
	TopBar.draw(ScriptBuilderScreen.topBar(screen), screen.tool, w, top)
	if screen.scene then
		BuilderColumn.draw(ScriptBuilderScreen.column(screen), function(name, content)
			if name == "plane" then
				WorkPlaneSection.draw(ScriptBuilderScreen.workPlane(screen))
			elseif name == "tree" then
				TreePanel.draw(ScriptBuilderScreen.treeRows(screen), content, screen.scene, screen.rename, screen.locked, screen.mouse)
			elseif name == "actions" then
				ActionPanel.draw(ScriptBuilderScreen.actionPanel(screen), screen.mouse)
			elseif name == "properties" then
				PropertiesStrip.draw(ScriptBuilderScreen.properties(screen), screen.field)
			elseif name == "params" then
				ParamsPanel.draw(ScriptBuilderScreen.paramsPanel(screen), screen.paramField)
			elseif name == "material" then
				MaterialPanel.draw(ScriptBuilderScreen.materialPanel(screen))
			else
				local id = screen.scene.selection[1]
				local shown = id and Scene.color(screen.scene, id)
				ColourPicker.draw(
					ScriptBuilderScreen.colourPicker(screen),
					screen.palette(),
					{ slot = shown, preset = shown },
					screen.mouse
				)
			end
		end)
	end
	local insertRows = ScriptBuilderScreen.insertMenu(screen)
	if insertRows then
		InsertMenu.draw(insertRows, screen.insert.armed, screen.mouse)
	end
	local shapeRows = ScriptBuilderScreen.shapeMenu(screen)
	if shapeRows then
		InsertMenu.draw(shapeRows, screen.shape.kind, screen.mouse)
	end
	if screen.menu then
		ContextMenu.draw(screen.menu, screen.mouse)
	end
	local codeLayout = ScriptBuilderScreen.codePanel(screen)
	if codeLayout then
		local c = screen.code
		local cfg = screen.config.designs
		local folder = love.filesystem.getSaveDirectory() .. "/" .. (screen.kind == "prefabs" and cfg.prefabDir or cfg.dir)
		CodePanel.draw(codeLayout, c.buffer, c.scroll, c.errorLine, folder, c.errorLine and screen.message)
	end
	if screen.exportPrompt then
		drawPrompt("Export as prefab: " .. screen.exportPrompt.text .. "_  (Return keeps, Esc drops)")
	end
	local libraryLayout = ScriptBuilderScreen.libraryPanel(screen)
	if libraryLayout then
		local palette = screen.palette()
		LibraryPanel.draw(libraryLayout, screen.libraryOpen and screen.libraryOpen.armed, screen.libraryOpen and screen.kind == screen.libraryOpen.tab and screen.name, screen.mouse, function(blueprint, rect)
			drawThumbnail(screen, blueprint, rect, palette)
		end)
	end
	if screen.libraryRename then
		drawPrompt("Rename " .. screen.libraryRename.name .. ": " .. screen.libraryRename.text .. "_  (Return keeps, Esc drops)")
	end
	if screen.unsaved then
		drawPrompt(screen.name .. " has unsaved changes: S saves, D discards, Esc stays")
	end
	ScriptBuilderView.drawStatus(screen)
	local open, openRow = ScriptBuilderScreen.dropdown(screen)
	if open then
		Dropdown.draw(open, openRow.value, screen.mouse)
	end
end

return ScriptBuilderScreen
