-- The world save's line records (src/game/save/records.lua).
local Records = require("src.game.save.records")

test("a record's fields round-trip with their types, odd strings included", function()
	local fields = { name = "Ünïcode % = \"quoted\"\nnew line", ratio = 0.1, n = 3, on = true, off = false }
	local line = Records.record("thing", fields)
	assertEqual(nil, line:find("\n"), "one line")
	local tag, back = Records.parse(line, 1)
	assertEqual("thing", tag)
	for k, v in pairs(fields) do
		assertEqual(v, back[k], k)
	end
end)

test("a record skips the field it is told to", function()
	local _, back = Records.parse(Records.record("node", { id = 1, reservedBy = "job" }, "reservedBy"), 1)
	assertEqual(1, back.id)
	assertEqual(nil, back.reservedBy)
end)

test("a bad value or escape is reported with its line, not thrown", function()
	for _, line in ipairs({ "thing x=q:7", "thing name=s:A%4", "thing x", "=n:1" }) do
		local tag, reason = Records.parse(line, 9)
		assertEqual(nil, tag, line)
		assertTrue(reason:find("line 9", 1, true), line)
	end
end)
