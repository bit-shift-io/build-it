-- The script builder (docs/CONTEXT.md § Script builder): a live 3D view of
-- a design script's geometry through the orbit camera, its footprint on the
-- ground, the numbered tool bar along the top, and the tree panel naming
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
-- A click on a tree row or on the model selects its node, Ctrl-click adds
-- to the selection, and a double-click on a row renames it. A right-click
-- without movement opens the context menu (Rename, Delete, Duplicate,
-- Group); right-drag orbits, the wheel zooms. Number keys and clicks pick
-- top bar tools. Ctrl+Z undoes, Ctrl+Y or Ctrl+Shift+Z redoes, Ctrl+S
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
-- Key 4 (Insert) opens a menu of primitives and prefabs, role prefabs
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
-- Key 2 (Shape) draws a closed 2D outline (src/game/builder/shape_tool.lua)
-- on the work plane (src/game/builder/work_plane.lua): the ground, an XY,
-- XZ or YZ plane at a height ([ and ] step it by a quarter tile) or a face
-- of the model picked from its menu. A rect or ellipse takes two clicks on
-- opposite corners; a polygon or path takes a click per point, and a path
-- point dragged while placed turns smooth with Bézier handles. Clicking
-- the first point again closes the outline into a shape node, one undo
-- step. Esc drops the outline being drawn, then puts the tool away. Shapes
-- show as outlines with no volume; the selected shape's points drag along
-- its plane, each move one undo step. The grid shows while Shape or
-- Insert is on, snapping to a quarter tile unless Shift is held; Insert
-- places on the same work plane.
--
-- Key 3 (Path) draws an open path (src/game/builder/path_tool.lua) on the
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
-- Key 5 (Material), or Material in the context menu, opens the material
-- panel (src/app/ui/material_panel.lua) under its slot, showing the first
-- selected node's material (its own or inherited, else the default). A
-- click on a material, a texture variant, or a scale or rotation stepper
-- makes every selected node of the result (Scene.setMaterial), one undo
-- step; clicks in the view still select. Esc puts the panel away.
local Compile = require("src.game.buildings.compile")
local Resolve = require("src.game.script.resolve")
local Lockcheck = require("src.game.script.lockcheck")
local Serialize = require("src.game.script.serialize")
local Scene = require("src.game.builder.scene")
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
local BuilderCamera = require("src.app.builder_camera")
local DesignStore = require("src.app.design_store")
local ScriptBuilderView = require("src.app.render.script_builder_view")
local Gizmo = require("src.app.render.gizmo")
local WorkPlaneView = require("src.app.render.work_plane")
local ShapeOverlay = require("src.app.render.shape_overlay")
local TopBar = require("src.app.ui.top_bar")
local TreePanel = require("src.app.ui.tree_panel")
local ContextMenu = require("src.app.ui.context_menu")
local InsertMenu = require("src.app.ui.insert_menu")
local PropertiesStrip = require("src.app.ui.properties")
local ParamsPanel = require("src.app.ui.params_panel")
local MaterialPanel = require("src.app.ui.material_panel")
local Screen = require("src.app.screen")

local ScriptBuilderScreen = {}

-- The top bar's tools by slot number.
ScriptBuilderScreen.TOOLS = {
	[1] = { id = "select", label = "Select" },
	[2] = { id = "shape", label = "Shape" },
	[3] = { id = "path", label = "Path" },
	[4] = { id = "insert", label = "Insert" },
	[5] = { id = "material", label = "Material" },
	[7] = { id = "library", label = "Library" },
}

-- The context menu's entries, top to bottom.
local MENU = { "Rename", "Delete", "Duplicate", "Group", "Extrude", "Lathe", "Sweep", "Material" }

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

-- Two left clicks on one row within this many seconds rename it.
local DOUBLE_CLICK = 0.4

local LOCKED_MESSAGE = "Locked script: it holds code, so edit it as text"

-- read(path) returns a game file's text, or nil and why not
-- (love.filesystem.read). library() returns the design library as it is
-- now (src/game/designs/library.lua), which its prefabs resolve from.
function ScriptBuilderScreen.new(config, read, library)
	return {
		config = config,
		cfg = config.builder,
		scfg = config.scriptBuilder,
		read = read,
		library = library,
		camera = BuilderCamera.new(config.builder),
		-- The design library this opening reads prefabs from.
		lib = nil,
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
		-- While the Shape or Path tool is on: { kinds (ShapeTool.KINDS or
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
	local blueprint, why = Compile.blueprint(resolved.root, screen.config)
	show(screen, blueprint, resolved.root, why or message)
end

-- The design name of a file path: its file name without ".lua".
local function nameOf(path)
	return path:match("([^/]+)%.lua$") or path
end

-- Reads and checks the design, showing it or why it failed.
function ScriptBuilderScreen.open(screen)
	local path = screen.scfg.testDesign
	screen.name = nameOf(path)
	screen.lib = screen.library()
	screen.scene, screen.history, screen.locked = nil, History.new(), false
	screen.menu, screen.rename, screen.status, screen.transform = nil, nil, nil, nil
	screen.tool, screen.insert, screen.field = "select", nil, nil
	screen.shape, screen.pointDrag, screen.hover, screen.sweeping = nil, nil, nil, nil
	screen.plane, screen.planeName, screen.planeHeight = WorkPlane.ground(), "Ground", 0
	screen.params, screen.paramField = {}, nil
	screen.materialOpen = nil
	local source, err = screen.lib.designs[screen.name], nil
	screen.chunk = screen.name
	if not source then
		source, err = screen.read(path)
		screen.chunk = path
	end
	screen.source = source
	if not source then
		show(screen, nil, nil, "Can't read " .. path .. ": " .. tostring(err))
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

-- Whether a menu or text box has the keyboard: Esc closes it, not the
-- builder.
function ScriptBuilderScreen.modal(screen)
	return screen.menu ~= nil or screen.rename ~= nil or screen.transform ~= nil
		or screen.field ~= nil or screen.insert ~= nil or screen.paramField ~= nil
		or screen.shape ~= nil or screen.pointDrag ~= nil or screen.sweeping ~= nil
		or screen.materialOpen ~= nil
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

-- Writes the design file: the scene written out, or the locked script as
-- it was read.
local function save(screen)
	if not screen.source then
		return
	end
	local ok, err = DesignStore.write(screen.config.designs, "designs", screen.name, text(screen))
	if ok then
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

-- The tree panel's rows (TreePanel.rows); none when the script failed.
function ScriptBuilderScreen.treeRows(screen)
	if not screen.scene then
		return {}
	end
	return TreePanel.rows(screen.scene, screen.scfg.topBarHeight)
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

-- The node under screen point (x, y): its tree row's, else the model's;
-- and whether the point is on the tree panel.
local function nodeAt(screen, x, y)
	local rows = ScriptBuilderScreen.treeRows(screen)
	local row = TreePanel.rowAt(rows, x, y)
	if row then
		return row.node.id, true
	end
	if screen.scene and TreePanel.contains(rows, screen.scfg.topBarHeight, x, y) then
		return nil, true
	end
	if y < screen.scfg.topBarHeight then
		return nil, true
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

local function select(screen, id, add)
	if screen.scene then
		Scene.select(screen.scene, id, add)
		screen.revision = screen.revision + 1
	end
end

-- The Insert tool's menu rows (InsertMenu.rows) under its top bar slot,
-- or nil when the tool is off.
function ScriptBuilderScreen.insertMenu(screen)
	if not screen.insert then
		return nil
	end
	for _, slot in ipairs(ScriptBuilderScreen.topBar(screen)) do
		if slot.tool and slot.tool.id == "insert" then
			return InsertMenu.rows(screen.insert.items, slot)
		end
	end
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

-- The material panel's rows (MaterialPanel.rows) under its top bar slot,
-- or nil when it is closed.
function ScriptBuilderScreen.materialPanel(screen)
	if not screen.materialOpen then
		return nil
	end
	for _, slot in ipairs(ScriptBuilderScreen.topBar(screen)) do
		if slot.tool and slot.tool.id == "material" then
			return MaterialPanel.rows(shownMaterial(screen), screen.config.materials, slot)
		end
	end
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

-- The properties strip's fields (PropertiesStrip.fields) for the one
-- selected node; none unless exactly one editable primitive is selected.
function ScriptBuilderScreen.properties(screen)
	local scene = screen.scene
	if screen.locked or not scene or #scene.selection ~= 1 then
		return {}
	end
	local node = Scene.find(scene, scene.selection[1])
	if not node then
		return {}
	end
	local w = Screen.dimensions()
	return PropertiesStrip.fields(Properties.of(node), w, screen.scfg.topBarHeight)
end

-- The params panel's rows (ParamsPanel.rows), one per declared param.
function ScriptBuilderScreen.paramsPanel(screen)
	local w = Screen.dimensions()
	return ParamsPanel.rows(screen.params, w, screen.scfg.topBarHeight)
end

-- Sets the param at `index` to `value`, clamped: its default rewritten in
-- the script's text, the design rebuilt. A bad value is refused with why.
local function setParam(screen, index, value)
	local param = screen.params[index]
	local clamped, why = Params.clamp(param, value)
	if clamped == nil then
		screen.message = param.label .. " " .. why
		return
	end
	if not param.name then
		screen.message = param.label .. " is not declared at the top level, so edit it as text"
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
	local param = screen.params[f.index]
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

-- The work planes the Shape menu offers, after the kinds it draws.
local PLANES = {
	{ label = "Ground", plane = "Ground" },
	{ label = "XY plane", plane = "XY" },
	{ label = "XZ plane", plane = "XZ" },
	{ label = "YZ plane", plane = "YZ" },
	{ label = "Pick face", plane = "Face" },
}

-- The Shape or Path tool's menu rows (InsertMenu.rows) under its top bar
-- slot: the kinds it draws, then the work planes, the one in use marked
-- with its height; nil when neither tool is on.
function ScriptBuilderScreen.shapeMenu(screen)
	if not screen.shape then
		return nil
	end
	local items = {}
	for i, item in ipairs(screen.shape.kinds) do
		items[i] = item
	end
	for _, item in ipairs(PLANES) do
		local label = item.label
		if item.plane == screen.planeName then
			local axis = screen.planeName ~= "Ground" and screen.planeName ~= "Face"
			label = "> " .. label .. (axis and " at " .. screen.planeHeight or "")
		end
		items[#items + 1] = { label = label, plane = item.plane }
	end
	for _, slot in ipairs(ScriptBuilderScreen.topBar(screen)) do
		if slot.tool and slot.tool.id == screen.tool then
			return InsertMenu.rows(items, slot)
		end
	end
end

-- Makes axis plane `name` at the current height, or the ground, the work
-- plane.
local function setPlane(screen, name)
	screen.planeName = name
	screen.plane = name == "Ground" and WorkPlane.ground() or WorkPlane.axis(name, screen.planeHeight)
	screen.shape.drawing = nil
end

-- Adopts the model's face under screen point (x, y) as the work plane;
-- nothing there leaves the plane as it was.
local function adoptFace(screen, x, y)
	screen.shape.picking = nil
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

-- A click with the Shape or Path tool at screen point (x, y) in the view.
local function shapeClick(screen, x, y)
	local tool = screen.shape
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

-- What the shape overlay (src/app/render/shape_overlay.lua) draws, in
-- design space: every shape's outline and every path (selected ones
-- marked), the selected shape's points and their handles, and the outline
-- or path under way.
function ScriptBuilderScreen.overlay(screen)
	local out = { outlines = {}, points = {} }
	if not screen.scene then
		return out
	end
	for _, s in ipairs(WorkPlane.shapes(screen.scene.root)) do
		out.outlines[#out.outlines + 1] = { corners = s.outline, closed = true, selected = Scene.isSelected(screen.scene, s.id) }
	end
	for _, p in ipairs(WorkPlane.paths(screen.scene.root)) do
		out.outlines[#out.outlines + 1] = { corners = p.points, closed = false, selected = Scene.isSelected(screen.scene, p.id) }
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
		for _, p in ipairs(screen.shape.drawing.points) do
			out.points[#out.points + 1] = { at = WorkPlane.at(screen.plane, p[1], p[2]) }
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
	Material = function(screen)
		for slot, tool in pairs(ScriptBuilderScreen.TOOLS) do
			if tool.id == "material" then
				setTool(screen, slot)
			end
		end
	end,
	-- Waits for a click on the path to sweep the selected shape along.
	Sweep = function(screen)
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

-- How far screen point (x, y) lies from the segment between pixels a and
-- b ({ x, y } each).
local function fromSegment(x, y, a, b)
	local dx, dy = b[1] - a[1], b[2] - a[2]
	local len2 = dx * dx + dy * dy
	local t = len2 > 0 and math.max(0, math.min(1, ((x - a[1]) * dx + (y - a[2]) * dy) / len2)) or 0
	local px, py = a[1] + dx * t - x, a[2] + dy * t - y
	return math.sqrt(px * px + py * py)
end

-- The id of the path drawn nearest screen point (x, y), within reach, or
-- nil.
local function pathAt(screen, x, y)
	local view, s = ScriptBuilderScreen.view(screen), screen.cfg.studsPerTile
	local best, nearest = nil, POINT_REACH
	for _, p in ipairs(WorkPlane.paths(screen.scene.root)) do
		local before = nil
		for _, point in ipairs(p.points) do
			local px, py = WorkPlaneView.pixel(view, s, screen.origin, point)
			local here = px and { px, py }
			if here and before then
				local d = fromSegment(x, y, before, here)
				if d <= nearest then
					best, nearest = p.id, d
				end
			end
			before = here
		end
	end
	return best
end

-- The click after Sweep: the path under it (its tree row, or drawn in the
-- view) gets the shape swept along it, one undo step.
local function sweepClick(screen, x, y)
	local shape = screen.sweeping.id
	screen.sweeping = nil
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
	screen.insert, screen.shape, screen.materialOpen = nil, nil, nil
	if tool.id == "insert" or tool.id == "shape" or tool.id == "path" or tool.id == "material" then
		if not screen.scene then
			return
		elseif screen.locked then
			screen.message = LOCKED_MESSAGE
			return
		end
	end
	if tool.id == "insert" then
		screen.insert = { items = Insert.items(screen.lib) }
	elseif tool.id == "shape" then
		screen.shape = { kinds = ShapeTool.KINDS, kind = ShapeTool.KINDS[4] }
	elseif tool.id == "path" then
		screen.shape = { kinds = PathTool.KINDS, kind = PathTool.KINDS[2], path = true }
	elseif tool.id == "material" then
		screen.materialOpen = true
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

-- A left click at (x, y) outside any menu.
local function leftClick(screen, x, y)
	if screen.sweeping then
		sweepClick(screen, x, y)
		return
	end
	local slot = TopBar.slotAt(ScriptBuilderScreen.topBar(screen), x, y)
	if slot then
		setTool(screen, slot.number)
		return
	end
	local menu = ScriptBuilderScreen.insertMenu(screen)
	local row = menu and InsertMenu.rowAt(menu, x, y)
	if row then
		screen.insert.armed = row.item
		return
	end
	local shapeRows = ScriptBuilderScreen.shapeMenu(screen)
	local shapeRow = shapeRows and InsertMenu.rowAt(shapeRows, x, y)
	if shapeRow then
		local item = shapeRow.item
		if item.kind or item.curve then
			screen.shape.kind, screen.shape.drawing = item, nil
		elseif item.plane == "Face" then
			screen.shape.picking, screen.shape.drawing = true, nil
		else
			setPlane(screen, item.plane)
		end
		return
	end
	local materialRow, materialPart = MaterialPanel.hit(ScriptBuilderScreen.materialPanel(screen), x, y)
	if materialRow then
		materialClick(screen, materialRow, materialPart)
		return
	end
	local paramRows = ScriptBuilderScreen.paramsPanel(screen)
	local paramRow, part = ParamsPanel.hit(paramRows, x, y)
	if paramRow then
		paramClick(screen, paramRow, part)
		return
	elseif ParamsPanel.contains(paramRows, x, y) then
		return
	end
	local field = PropertiesStrip.fieldAt(ScriptBuilderScreen.properties(screen), x, y)
	if field then
		startField(screen, field)
		return
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
	if screen.tool == "select" or screen.tool == "material" then
		select(screen, id, ctrlDown())
	end
end

function ScriptBuilderScreen.update(screen, dt)
	screen.clock = screen.clock + dt
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
		local item = ContextMenu.itemAt(screen.menu, x, y)
		screen.menu = nil
		if item then
			ACTIONS[item](screen)
		end
		return
	end
	leftClick(screen, x, y)
end

-- A right-click without movement opens the context menu on the node under
-- the pointer, selecting it first unless it is selected already.
function ScriptBuilderScreen.mousereleased(screen, x, y, button)
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
	screen.menu = ContextMenu.open(x, y, MENU)
end

function ScriptBuilderScreen.mousemoved(screen, x, y, dx, dy)
	screen.mouse = { x = x, y = y }
	screen.hover = (screen.shape or screen.insert) and planeHit(screen, x, y) or nil
	local drawing = screen.shape and screen.shape.drawing
	if screen.transform then
		follow(screen, x, y)
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
	elseif screen.rename then
		renameKey(screen, key)
	elseif screen.field then
		fieldKey(screen, key)
	elseif screen.paramField then
		paramFieldKey(screen, key)
	elseif screen.menu then
		if key == "escape" then
			screen.menu = nil
		end
	elseif key == "escape" and screen.sweeping then
		screen.sweeping, screen.message = nil, nil
	elseif (key == "return" or key == "kpenter") and screen.shape and screen.shape.path and screen.shape.drawing then
		finishPath(screen)
	elseif key == "escape" and screen.materialOpen then
		screen.materialOpen, screen.tool = nil, "select"
	elseif key == "escape" and screen.insert then
		screen.insert, screen.tool = nil, "select"
	elseif key == "escape" and screen.shape and (screen.shape.drawing or screen.shape.picking) then
		screen.shape.drawing, screen.shape.picking = nil, nil
	elseif key == "escape" and screen.shape then
		screen.shape, screen.tool = nil, "select"
	elseif (key == "[" or key == "]") and screen.shape then
		local name = screen.planeName
		if name == "XY" or name == "XZ" or name == "YZ" then
			screen.planeHeight = screen.planeHeight + (key == "]" and WorkPlane.SNAP or -WorkPlane.SNAP)
			setPlane(screen, name)
		end
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
	if screen.rename then
		screen.rename.text = screen.rename.text .. typed
	elseif screen.field then
		screen.field.text = screen.field.text .. typed
	elseif screen.paramField then
		screen.paramField.text = screen.paramField.text .. typed
	end
end

function ScriptBuilderScreen.draw(screen)
	local w = Screen.dimensions()
	local top = screen.scfg.topBarHeight
	ScriptBuilderView.draw(screen, ScriptBuilderScreen.view(screen))
	local view = ScriptBuilderScreen.view(screen)
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
		TreePanel.draw(ScriptBuilderScreen.treeRows(screen), top, screen.scene, screen.rename, screen.locked, screen.mouse)
	end
	PropertiesStrip.draw(ScriptBuilderScreen.properties(screen), screen.field)
	ParamsPanel.draw(ScriptBuilderScreen.paramsPanel(screen), screen.paramField)
	local insertRows = ScriptBuilderScreen.insertMenu(screen)
	if insertRows then
		InsertMenu.draw(insertRows, screen.insert.armed, screen.mouse)
	end
	local shapeRows = ScriptBuilderScreen.shapeMenu(screen)
	if shapeRows then
		InsertMenu.draw(shapeRows, screen.shape.kind, screen.mouse)
	end
	local materialRows = ScriptBuilderScreen.materialPanel(screen)
	if materialRows then
		MaterialPanel.draw(materialRows, shownMaterial(screen), screen.mouse)
	end
	if screen.menu then
		ContextMenu.draw(screen.menu, screen.mouse)
	end
	ScriptBuilderView.drawStatus(screen)
end

return ScriptBuilderScreen
