-- Undo and redo for a draft (src/game/builder/draft.lua). Pure -- no
-- `love.*`.
--
--   { past = { <snapshot>, ... }, future = { <snapshot>, ... } }
--
-- Every draft change goes through History.apply, which snapshots the draft
-- first and keeps the snapshot only when the change took. Snapshots are
-- whole copies of the draft: drafts are small, and a copy restores exactly.
local History = {}

function History.new()
	return { past = {}, future = {} }
end

local function copyBricks(bricks)
	local out = {}
	for i, b in ipairs(bricks) do
		local copy = {}
		for k, v in pairs(b) do
			copy[k] = v
		end
		out[i] = copy
	end
	return out
end

local function snapshot(draft)
	return { width = draft.width, depth = draft.depth, bricks = copyBricks(draft.bricks) }
end

local function restore(draft, s)
	draft.width, draft.depth, draft.bricks = s.width, s.depth, copyBricks(s.bricks)
end

-- Runs change(draft, ...), a draft edit such as Draft.place, and returns
-- what it returns. When its first result is truthy the change counts: it
-- can be undone, and anything undone before it can no longer be redone.
function History.apply(history, draft, change, ...)
	local before = snapshot(draft)
	local results = { change(draft, ...) }
	if results[1] then
		table.insert(history.past, before)
		history.future = {}
	end
	return unpack(results, 1, table.maxn(results))
end

-- Steps `draft` back before the last change. False when there is none.
function History.undo(history, draft)
	local s = table.remove(history.past)
	if not s then
		return false
	end
	table.insert(history.future, snapshot(draft))
	restore(draft, s)
	return true
end

-- Steps `draft` forward over the last undo. False when there is none.
function History.redo(history, draft)
	local s = table.remove(history.future)
	if not s then
		return false
	end
	table.insert(history.past, snapshot(draft))
	restore(draft, s)
	return true
end

return History
