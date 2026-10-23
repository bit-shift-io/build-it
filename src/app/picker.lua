-- The building picker's state (docs/CONTEXT.md "Building picker"): the
-- search query, the designs matching it, and how far the list is scrolled.
-- Pure: no drawing and no devices, so it runs under plain LuaJIT.
local Picker = {}

-- How many rows the picker shows at once.
Picker.ROWS = 12

-- designs: the placeable designs, { name, blueprint } each, by name
-- (src/game/designs/library.lua Library.placeable).
function Picker.new(designs)
	return { designs = designs, query = "", scroll = 0 }
end

-- The designs whose name contains the query, ignoring case.
function Picker.matches(picker)
	local needle = picker.query:lower()
	local out = {}
	for _, design in ipairs(picker.designs) do
		if design.name:lower():find(needle, 1, true) then
			out[#out + 1] = design
		end
	end
	return out
end

local function clamp(picker)
	local last = math.max(0, #Picker.matches(picker) - Picker.ROWS)
	picker.scroll = math.max(0, math.min(last, picker.scroll))
end

-- Adds typed text to the query; the list returns to the top.
function Picker.type(picker, text)
	picker.query = picker.query .. text
	picker.scroll = 0
end

-- Removes the query's last character (UTF-8 aware).
function Picker.backspace(picker)
	picker.query = picker.query:match("^(.-)[^\128-\191]?[\128-\191]*$")
	picker.scroll = 0
end

-- Scrolls by `rows` (positive moves down), clamped to the list.
function Picker.scrollBy(picker, rows)
	picker.scroll = picker.scroll + rows
	clamp(picker)
end

-- The matches in view: at most ROWS designs from the scroll offset.
function Picker.visible(picker)
	local out = {}
	for i, design in ipairs(Picker.matches(picker)) do
		if i > picker.scroll and i <= picker.scroll + Picker.ROWS then
			out[#out + 1] = design
		end
	end
	return out
end

return Picker
