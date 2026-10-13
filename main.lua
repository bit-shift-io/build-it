-- `debug` launch arg (see .vscode/launch.json) attaches the Local Lua Debugger when the extension puts
-- lldebugger on LUA_PATH; plain `./run.sh` runs are unaffected.
for _, a in ipairs(arg or {}) do
	if a == "debug" then
		local ok, debugger = pcall(require, "lldebugger")
		if ok then
			debugger.start()
		else
			print("lldebugger not found; continuing without debugger")
		end
		break
	end
end

require("src.app.main")
