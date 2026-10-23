-- Undo and redo for the builder's scene (src/game/builder/scene.lua). Pure;
-- plain LuaJIT.
--
--   { past = { <snapshot>, ... }, future = { <snapshot>, ... } }
--
-- Every scene edit goes through History.apply, which snapshots the scene
-- first and keeps the snapshot only when the edit took. A snapshot is a
-- whole copy of the node tree and the selection: design trees are small,
-- and a copy restores exactly.
local Scene = require("src.game.builder.scene")

local History = {}

function History.new()
	return { past = {}, future = {} }
end

local function snapshot(scene)
	return { root = Scene.copy(scene.root), selection = Scene.copy(scene.selection) }
end

local function restore(scene, s)
	scene.root, scene.selection = Scene.copy(s.root), Scene.copy(s.selection)
end

-- Runs change(scene, ...), a scene edit such as Scene.rename, and returns
-- what it returns. When its first result is truthy the edit counts: it can
-- be undone, and anything undone before it can no longer be redone.
function History.apply(history, scene, change, ...)
	local before = snapshot(scene)
	local results = { change(scene, ...) }
	if results[1] then
		table.insert(history.past, before)
		history.future = {}
	end
	return unpack(results, 1, table.maxn(results))
end

-- Steps `scene` back before the last edit. False when there is none.
function History.undo(history, scene)
	local s = table.remove(history.past)
	if not s then
		return false
	end
	table.insert(history.future, snapshot(scene))
	restore(scene, s)
	return true
end

-- Steps `scene` forward over the last undo. False when there is none.
function History.redo(history, scene)
	local s = table.remove(history.future)
	if not s then
		return false
	end
	table.insert(history.past, snapshot(scene))
	restore(scene, s)
	return true
end

return History
