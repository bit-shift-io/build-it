-- The building picker's pure state (src/app/picker.lua) and its row
-- geometry (src/app/render/picker.lua).
local Picker = require("src.app.picker")
local PickerRender = require("src.app.render.picker")

local function designs(...)
	local out = {}
	for i, name in ipairs({ ... }) do
		out[i] = { id = "d" .. i, name = name }
	end
	return out
end

local function many(n)
	local out = {}
	for i = 1, n do
		out[i] = { id = "d" .. i, name = "Design " .. i }
	end
	return out
end

test("an empty query lists every design", function()
	local p = Picker.new(designs("Hall", "Mill", "Hut"))
	assertEqual(3, #Picker.matches(p))
end)

test("the query matches a substring, ignoring case", function()
	local p = Picker.new(designs("Hall", "Sawmill", "Hut"))
	Picker.type(p, "MI")
	local found = Picker.matches(p)
	assertEqual(1, #found)
	assertEqual("Sawmill", found[1].name)
end)

test("backspace removes the last character", function()
	local p = Picker.new(designs("Hall", "Hut"))
	Picker.type(p, "hu")
	assertEqual(1, #Picker.matches(p))
	Picker.backspace(p)
	assertEqual("h", p.query)
	assertEqual(2, #Picker.matches(p))
	Picker.backspace(p)
	Picker.backspace(p)
	assertEqual("", p.query)
end)

test("scrolling clamps to the list", function()
	local p = Picker.new(many(15))
	Picker.scrollBy(p, -3)
	assertEqual(0, p.scroll)
	Picker.scrollBy(p, 100)
	assertEqual(15 - Picker.ROWS, p.scroll)
	local visible = Picker.visible(p)
	assertEqual(Picker.ROWS, #visible)
	assertEqual("Design 15", visible[#visible].name)
end)

test("a short list does not scroll", function()
	local p = Picker.new(many(3))
	Picker.scrollBy(p, 5)
	assertEqual(0, p.scroll)
end)

test("typing returns the list to the top", function()
	local p = Picker.new(many(20))
	Picker.scrollBy(p, 5)
	Picker.type(p, "d")
	assertEqual(0, p.scroll)
end)

test("designAt finds the design under a row", function()
	local p = Picker.new(designs("Hall", "Hut"))
	local row = PickerRender.row(1280, 720, 2)
	assertEqual("Hut", PickerRender.designAt(p, 1280, 720, row.x + 5, row.y + 5).name)
	assertEqual(nil, PickerRender.designAt(p, 1280, 720, row.x + 5, row.y + 5 + 3 * row.h))
end)

test("cost parts list items sorted, flagging those the totals can't cover", function()
	local parts = PickerRender.costParts({ stone = 5, plank = 10 }, { plank = 10, stone = 2 })
	assertEqual(2, #parts)
	assertEqual("10 plank", parts[1].text)
	assertFalse(parts[1].short)
	assertEqual("5 stone", parts[2].text)
	assertTrue(parts[2].short)
end)
