-- The design library on disk (src/app/design_store.lua): design and prefab
-- scripts as Lua files in two folders of love_mock's real save directory.
local LoveMock = require("tests.support.love_mock")
local DesignStore = require("src.app.design_store")
local Config = require("src.game.config")

local CFG = Config.designs

test("the library reads every Lua file of both folders, named by file name", function()
	_G.love = LoveMock.new()
	love.filesystem.createDirectory(CFG.dir)
	love.filesystem.createDirectory(CFG.prefabDir)
	assert(love.filesystem.write(CFG.dir .. "/hut.lua", "return box{}"))
	assert(love.filesystem.write(CFG.prefabDir .. "/lamp.lua", "return sphere{}"))
	local lib = DesignStore.load(CFG)
	assertEqual("return box{}", lib.designs.hut)
	assertEqual("return sphere{}", lib.prefabs.lamp)
	assertEqual(nil, lib.designs.lamp)
end)

test("old brick .design files and .tmp leftovers are ignored", function()
	_G.love = LoveMock.new()
	love.filesystem.createDirectory(CFG.dir)
	assert(love.filesystem.write(CFG.dir .. "/d1.design", "build-it-design 1\n"))
	assert(love.filesystem.write(CFG.dir .. "/hut.lua.tmp", "half"))
	local lib = DesignStore.load(CFG)
	assertEqual(nil, next(lib.designs))
	assertEqual(nil, next(lib.prefabs), "a missing folder is empty")
end)

test("writing a script puts it in its kind's folder, replacing the old file whole", function()
	_G.love = LoveMock.new()
	assert(DesignStore.write(CFG, "designs", "hut", "return box{}"))
	assert(DesignStore.write(CFG, "designs", "hut", "return sphere{}"))
	assert(DesignStore.write(CFG, "prefabs", "lamp", "return box{}"))
	local lib = DesignStore.load(CFG)
	assertEqual("return sphere{}", lib.designs.hut)
	assertEqual("return box{}", lib.prefabs.lamp)
	assertEqual(nil, love.filesystem.getInfo(CFG.dir .. "/hut.lua.tmp"), "no leftover")
end)

test("a name that isn't a plain file name is refused", function()
	_G.love = LoveMock.new()
	for _, name in ipairs({ "../world", "a/b", "", "x.lua" }) do
		local ok, err = DesignStore.write(CFG, "designs", name, "return box{}")
		assertEqual(nil, ok, name)
		assertTrue(err, name)
	end
end)
