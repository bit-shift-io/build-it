-- The Work plane section's pure layout: plane buttons, the height stepper.
local WorkPlaneSection = require("src.app.ui.work_plane_section")

local CONTENT = { x = 8, y = 100, width = 220 }

test("the section has five plane buttons inside the column width, the current one marked", function()
	local l = WorkPlaneSection.layout("YZ", 0, CONTENT)
	assertEqual(5, #l.buttons)
	for _, b in ipairs(l.buttons) do
		assertTrue(b.x >= 8 and b.x + b.width <= 228, b.plane .. " fits")
		assertEqual(b.plane == "YZ", b.current)
	end
	local b = l.buttons[2]
	assertEqual("XY", WorkPlaneSection.hit(l, b.x + 1, b.y + 1).plane)
end)

test("only an axis plane has a height stepper, and its boxes step down and up", function()
	assertEqual(nil, WorkPlaneSection.layout("Ground", 0, CONTENT).stepper)
	assertEqual(nil, WorkPlaneSection.layout("Face", 0, CONTENT).stepper)
	assertTrue(WorkPlaneSection.height("XZ") > WorkPlaneSection.height("Ground"))
	local l = WorkPlaneSection.layout("XZ", 0.25, CONTENT)
	assertEqual("Height 0.25", l.stepper.label)
	assertEqual(1, WorkPlaneSection.hit(l, l.stepper.plus.x + 1, l.stepper.plus.y + 1).step)
	assertEqual(-1, WorkPlaneSection.hit(l, l.stepper.minus.x + 1, l.stepper.minus.y + 1).step)
	assertEqual(nil, WorkPlaneSection.hit(l, 1000, 1000))
end)
