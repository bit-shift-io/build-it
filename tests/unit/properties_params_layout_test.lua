-- The Properties and Params sections' stacked layout: each entry a label
-- over a full-width input, all inside the column's 220 px.
local PropertiesStrip = require("src.app.ui.properties")
local ParamsPanel = require("src.app.ui.params_panel")

test("properties stack top to bottom, each box the content's full width", function()
	local fields = PropertiesStrip.fields({ { key = "w", label = "Width", value = 1 }, { key = "d", label = "Depth", value = 2 } }, 8, 100, 220)
	assertEqual(2, #fields)
	assertEqual(8, fields[1].x)
	assertEqual(220, fields[1].width)
	assertTrue(fields[1].y > fields[1].labelY, "the box sits under its label")
	assertTrue(fields[2].labelY >= fields[1].y + fields[1].height, "the next entry starts below")
	assertEqual(PropertiesStrip.height(2), fields[2].y + fields[2].height + 6 - 100)
end)

test("a number param is - value + across the width; a bool is one wide box", function()
	local rows = ParamsPanel.rows({ { kind = "number", label = "n", value = 1 }, { kind = "bool", label = "b", value = true } }, 8, 0, 220)
	local n, b = rows[1], rows[2]
	assertEqual(8, n.minus.x)
	assertEqual(8 + 220, n.plus.x + n.plus.width)
	assertTrue(n.minus.x + n.minus.width <= n.value.x and n.value.x + n.value.width <= n.plus.x, "value between the steppers")
	assertEqual(220, b.value.width)
	assertEqual(nil, b.minus)
	assertTrue(b.labelY >= n.y + n.value.height, "stacked")
end)

test("long labels are clipped to the width", function()
	local clipped = ParamsPanel.clip(string.rep("x", 60), 220)
	assertTrue(#clipped * 7 <= 220)
	assertEqual("short", PropertiesStrip.clip("short", 220))
end)
