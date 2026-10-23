-- The builder colour picker's recent-colours row: the last 8 picks, newest
-- first, a repeat moving to the front.
local RecentColours = require("src.game.builder.recent_colours")

test("recent colours keep the last 8 picks, newest first", function()
	local recent = RecentColours.new()
	for i = 1, 10 do
		RecentColours.add(recent, { i / 10, 0, 0 })
	end
	assertEqual(8, #recent)
	assertEqual(1, recent[1][1])
	assertEqual(0.3, recent[8][1])
end)

test("picking a colour again moves it to the front; slots count as colours", function()
	local recent = RecentColours.new()
	local red = { 1, 0, 0 }
	RecentColours.add(recent, red)
	RecentColours.add(recent, "primary")
	RecentColours.add(recent, { 1, 0, 0 })
	RecentColours.add(recent, "primary")
	assertEqual(2, #recent)
	assertEqual("primary", recent[1])
	assertEqual(1, recent[2][1])
	red[2] = 1
	assertEqual(0, recent[2][2], "the list keeps its own copy")
end)
