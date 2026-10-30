-- The dropdown's pure layout: the closed box, the option list, flipping.
local Dropdown = require("src.app.ui.dropdown")

local BOX = { x = 10, y = 100, width = 100, height = 20 }
local OPTIONS = { { value = "a", label = "A" }, { value = "b", label = "B" } }

test("a closed dropdown has only its box, and hits it", function()
	local l = Dropdown.layout(BOX, OPTIONS, false, 600)
	assertEqual(nil, l.list)
	assertEqual("box", (Dropdown.hit(l, 20, 110)))
	assertEqual(nil, Dropdown.hit(l, 20, 130))
end)

test("an open list sits under the box, one item per option, and hits them", function()
	local l = Dropdown.layout(BOX, OPTIONS, true, 600)
	assertEqual(120, l.list.y)
	assertEqual(40, l.list.height)
	local kind, option = Dropdown.hit(l, 20, 145)
	assertEqual("option", kind)
	assertEqual("b", option.value)
	assertTrue(Dropdown.contains(l, 20, 125))
	assertEqual(nil, Dropdown.hit(l, 500, 500))
end)

test("the list flips above the box when it would run past the window bottom", function()
	local l = Dropdown.layout(BOX, OPTIONS, true, 130)
	assertEqual(60, l.list.y)
	local _, option = Dropdown.hit(l, 20, 65)
	assertEqual("a", option.value)
end)
