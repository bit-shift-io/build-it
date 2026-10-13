-- LÖVE 12 only (docs/adr/0002-love-12-dev-build-only.md).
function love.conf(t)
	t.identity = "build-it"
	t.version = "12.0"
	t.window.title = "Build-it"
	t.window.width = 1280
	t.window.height = 720
	t.window.resizable = true
	t.window.minwidth = 1
	t.window.minheight = 1
	t.window.vsync = 1
end
