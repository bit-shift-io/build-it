-- The team palette (docs/CONTEXT.md "Team palette"): a player's colour
-- slots, derived from the two colours in their Settings. A node's colour is
-- a literal { r, g, b } or one of these slot names; slots resolve to the
-- owner's palette at bake (src/app/bake/baker.lua). Pure; plain LuaJIT.
--
--   { primary, primaryDark, primaryLight, secondary, secondaryDark,
--     secondaryLight, highlight }   each { r, g, b }, channels 0 to 1
local Palette = {}

-- Every slot name, in the order the colour picker shows them.
Palette.SLOTS = { "primary", "primaryDark", "primaryLight", "secondary", "secondaryDark", "secondaryLight", "highlight" }

local IS_SLOT = {}
for _, slot in ipairs(Palette.SLOTS) do
	IS_SLOT[slot] = true
end

-- How far a dark shade goes toward black, a light one toward white, and the
-- highlight (from primary) toward white.
local DARK, LIGHT, HIGHLIGHT = 0.4, 0.4, 0.75

-- The two colours a player starts with.
Palette.DEFAULT_PRIMARY = { 0.75, 0.22, 0.18 }
Palette.DEFAULT_SECONDARY = { 0.2, 0.36, 0.7 }

-- `c` moved a fraction `t` of the way to `to`.
local function toward(c, to, t)
	return { c[1] + (to - c[1]) * t, c[2] + (to - c[2]) * t, c[3] + (to - c[3]) * t }
end

-- The palette of `primary` and `secondary` ({ r, g, b } each).
function Palette.derive(primary, secondary)
	return {
		primary = { primary[1], primary[2], primary[3] },
		primaryDark = toward(primary, 0, DARK),
		primaryLight = toward(primary, 1, LIGHT),
		secondary = { secondary[1], secondary[2], secondary[3] },
		secondaryDark = toward(secondary, 0, DARK),
		secondaryLight = toward(secondary, 1, LIGHT),
		highlight = toward(primary, 1, HIGHLIGHT),
	}
end

-- The palette of the default colours.
Palette.DEFAULT = Palette.derive(Palette.DEFAULT_PRIMARY, Palette.DEFAULT_SECONDARY)

-- `palette` as plain text (hex digits) that changes with any slot's colour,
-- for cache keys.
function Palette.key(palette)
	local out = {}
	for _, slot in ipairs(Palette.SLOTS) do
		for _, channel in ipairs(palette[slot]) do
			out[#out + 1] = string.format("%06x", math.floor(channel * 0xffffff + 0.5))
		end
	end
	return table.concat(out)
end

-- Whether `name` is a slot name.
function Palette.isSlot(name)
	return IS_SLOT[name] == true
end

return Palette
