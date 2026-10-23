-- The script builder colour picker's recent colours (docs/CONTEXT.md "Team
-- palette"): the last RecentColours.MAX picks, newest first, for the
-- session only (never saved). A colour is a node colour: { r, g, b } or a
-- team slot name. Pure; plain LuaJIT.
local RecentColours = {}

RecentColours.MAX = 8

function RecentColours.new()
	return {}
end

-- Whether colours `a` and `b` are the same slot or the same r, g, b.
function RecentColours.same(a, b)
	if type(a) ~= type(b) then
		return false
	elseif type(a) == "string" then
		return a == b
	end
	return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

-- Puts `color` (a copy) first in `recent`, dropping an earlier pick of the
-- same colour and any past the MAX'th.
function RecentColours.add(recent, color)
	for i = #recent, 1, -1 do
		if RecentColours.same(recent[i], color) then
			table.remove(recent, i)
		end
	end
	table.insert(recent, 1, type(color) == "table" and { color[1], color[2], color[3] } or color)
	while #recent > RecentColours.MAX do
		table.remove(recent)
	end
end

return RecentColours
