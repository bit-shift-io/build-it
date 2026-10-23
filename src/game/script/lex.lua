-- A design script's tokens (docs/CONTEXT.md "Design script"), for the
-- checks and edits that read a script's text without running it: the lock
-- check (src/game/script/lockcheck.lua) and param default rewrites
-- (src/game/script/params.lua). Pure; plain LuaJIT. Never runs the text.
local Lex = {}

-- The position after a long bracket opening at `i` ([[, [==[ ...), or nil
-- when `i` opens none.
local function longBracketEnd(text, i)
	local equals = text:match("^%[(=*)%[", i)
	if not equals then
		return nil
	end
	local _, close = text:find("]" .. equals .. "]", i, true)
	return (close or #text) + 1
end

-- The position after a quoted string opening at `i`.
local function quotedEnd(text, i)
	local quote = text:sub(i, i)
	local j = i + 1
	while j <= #text do
		local c = text:sub(j, j)
		if c == "\\" then
			j = j + 2
		elseif c == quote then
			return j + 1
		else
			j = j + 1
		end
	end
	return j
end

-- `text`'s tokens, comments and space dropped: { { kind, text, first,
-- last }, ... }, kind "name" | "number" | "string" | "symbol", text the
-- name or symbol (nil for numbers and strings), first and last the
-- token's character positions in `text`.
function Lex.tokens(text)
	local out, i = {}, 1
	local function add(kind, j, word)
		out[#out + 1] = { kind = kind, text = word, first = i, last = j - 1 }
		i = j
	end
	while i <= #text do
		local c = text:sub(i, i)
		if c:match("%s") then
			i = i + 1
		elseif text:sub(i, i + 1) == "--" then
			i = longBracketEnd(text, i + 2) or (text:find("\n", i, true) or #text) + 1
		elseif c == "\"" or c == "'" then
			add("string", quotedEnd(text, i))
		elseif longBracketEnd(text, i) then
			add("string", longBracketEnd(text, i))
		elseif c:match("[%a_]") then
			local name = text:match("^[%w_]+", i)
			add("name", i + #name, name)
		elseif c:match("%d") or (c == "." and text:sub(i + 1, i + 1):match("%d")) then
			local n = text:match("^0[xX]%x+", i) or text:match("^%d*%.?%d*[eE][%+%-]?%d+", i) or text:match("^%d*%.?%d*", i)
			add("number", i + #n)
		else
			local symbol = text:match("^[=~<>]=", i) or text:match("^%.%.%.?", i) or c
			add("symbol", i + #symbol, symbol)
		end
	end
	return out
end

return Lex
