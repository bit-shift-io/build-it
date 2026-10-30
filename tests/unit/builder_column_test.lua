-- The builder column's pure layout: stacking, collapsing, hiding, scrolling.
local BuilderColumn = require("src.app.ui.builder_column")

local function sections(collapsedTree)
	return {
		{ name = "tree", title = "Tree", height = 100, collapsed = collapsedTree },
		{ name = "actions", title = "Actions", height = 50 },
	}
end

local function byName(col, name)
	for _, s in ipairs(col.sections) do
		if s.name == name then
			return s
		end
	end
end

test("sections stack down the column with a header over each content", function()
	local col = BuilderColumn.layout(sections(false), 30, 600, 0)
	local tree, actions = byName(col, "tree"), byName(col, "actions")
	assertEqual(220, col.width)
	assertEqual(tree.header.y + tree.header.height, tree.content.y)
	assert(actions.header.y >= tree.content.y + 100, "actions sit below the tree")
	assertEqual(nil, col.bar)
end)

test("a collapsed section is its header alone and pulls the next one up", function()
	local open = byName(BuilderColumn.layout(sections(false), 30, 600, 0), "actions")
	local col = BuilderColumn.layout(sections(true), 30, 600, 0)
	local tree = byName(col, "tree")
	assertEqual(nil, tree.content)
	assertEqual(true, tree.collapsed)
	assertEqual(open.header.y - 100, byName(col, "actions").header.y)
end)

test("a section with no height is hidden and takes no space", function()
	local col = BuilderColumn.layout({
		{ name = "tree", title = "Tree" },
		{ name = "actions", title = "Actions", height = 50 },
	}, 30, 600, 0)
	assertEqual(1, #col.sections)
	assertEqual(nil, byName(col, "tree"))
	assertEqual(col.y + 8, col.sections[1].header.y)
end)

test("scroll is clamped and shifts every section up", function()
	local still = BuilderColumn.layout(sections(false), 30, 100, 0)
	assert(still.maxScroll > 0)
	local col = BuilderColumn.layout(sections(false), 30, 100, 40)
	assertEqual(40, col.scroll)
	assertEqual(byName(still, "tree").header.y - 40, byName(col, "tree").header.y)
	assertEqual(still.maxScroll, BuilderColumn.layout(sections(false), 30, 100, 9999).scroll)
	assertEqual(0, BuilderColumn.layout(sections(false), 30, 100, -5).scroll)
	assertEqual(0, BuilderColumn.layout(sections(false), 30, 600, 50).scroll)
	assertEqual(5, BuilderColumn.clampScroll(col, 5))
	assertEqual(col.maxScroll, BuilderColumn.clampScroll(col, 1e6))
end)

test("the thumb is sized to the view and rides the track with the scroll", function()
	local top = BuilderColumn.layout(sections(false), 30, 100, 0)
	local bottom = BuilderColumn.layout(sections(false), 30, 100, 1e6)
	assert(top.bar.thumb.height < 100 and top.bar.thumb.height >= 20)
	assertEqual(30, top.bar.thumb.y)
	assertEqual(130, bottom.bar.thumb.y + bottom.bar.thumb.height)
	assert(top.bar.track.x >= top.x + top.width, "bar is right of the column")
end)

test("dragging the thumb maps the pointer to a scroll", function()
	local col = BuilderColumn.layout(sections(false), 30, 100, 0)
	local grab = 5
	assertEqual(0, BuilderColumn.dragScroll(col, grab, 0))
	assertEqual(col.maxScroll, BuilderColumn.dragScroll(col, grab, 1e6))
	local room = col.bar.track.height - col.bar.thumb.height
	local mid = BuilderColumn.dragScroll(col, grab, 30 + grab + room / 2)
	assert(math.abs(mid - col.maxScroll / 2) < 1e-6)
end)

test("hit finds headers, content, the bar, and nothing off the column", function()
	local col = BuilderColumn.layout(sections(false), 30, 100, 0)
	local tree = byName(col, "tree")
	assertEqual("header", BuilderColumn.hit(col, 20, tree.header.y + 2).part)
	assertEqual("tree", BuilderColumn.hit(col, 20, tree.content.y + 2).name)
	assertEqual("thumb", BuilderColumn.hit(col, col.bar.thumb.x + 1, col.bar.thumb.y + 1).part)
	assertEqual("track", BuilderColumn.hit(col, col.bar.track.x + 1, 129).part)
	assertEqual(nil, BuilderColumn.hit(col, 500, 50))
	assert(not BuilderColumn.contains(col, 20, 10), "above the column")
	assert(BuilderColumn.contains(col, 20, 50))
end)
