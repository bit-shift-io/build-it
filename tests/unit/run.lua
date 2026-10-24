-- Unit test runner: runs a fixed list of test files with no `love` global and
-- no LÖVE mock. Only src/core and src/game may be exercised here (see
-- docs/ARCHITECTURE.md) -- anything touching `love.*` belongs in a higher tier.
-- Register every new test file below or it never runs.
local defaultTestFiles = {
	"tests/unit/rng_test.lua",
	"tests/unit/picker_test.lua",
	"tests/unit/vec2_test.lua",
	"tests/unit/mover_test.lua",
	"tests/unit/session_test.lua",
	"tests/unit/camera_test.lua",
	"tests/unit/block_model_test.lua",
	"tests/unit/mesher_test.lua",
	"tests/unit/projection_test.lua",
	"tests/unit/settings_test.lua",
	"tests/unit/tree_prop_test.lua",
	"tests/unit/planter_test.lua",
	"tests/unit/growth_test.lua",
	"tests/unit/rock_prop_test.lua",
	"tests/unit/animal_system_test.lua",
	"tests/unit/bush_prop_test.lua",
	"tests/unit/deer_prop_test.lua",
	"tests/unit/world_gen_test.lua",
	"tests/unit/builder_camera_test.lua",
	"tests/unit/inventory_test.lua",
	"tests/unit/harvestable_test.lua",
	"tests/unit/design_library_test.lua",
	"tests/unit/placement_test.lua",
	"tests/unit/animator_test.lua",
	"tests/unit/character_prop_test.lua",
	"tests/unit/function_brick_test.lua",
	"tests/unit/converter_test.lua",
	"tests/unit/aura_test.lua",
	"tests/unit/reservation_test.lua",
	"tests/unit/storage_test.lua",
	"tests/unit/ports_test.lua",
	"tests/unit/save_codec_test.lua",
	"tests/unit/save_records_test.lua",
	"tests/unit/starter_design_test.lua",
	"tests/unit/starter_content_test.lua",
	"tests/unit/world_render_test.lua",
	"tests/unit/storage_facility_test.lua",
	"tests/unit/pathfind_test.lua",
	"tests/unit/walker_test.lua",
	"tests/unit/idle_test.lua",
	"tests/unit/load_test.lua",
	"tests/unit/haul_test.lua",
	"tests/unit/job_system_test.lua",
	"tests/unit/operate_test.lua",
	"tests/unit/site_test.lua",
	"tests/unit/blueprint_test.lua",
	"tests/unit/status_test.lua",
	"tests/unit/needs_test.lua",
	"tests/unit/eat_test.lua",
	"tests/unit/feed_test.lua",
	"tests/unit/sleep_test.lua",
	"tests/unit/hud_test.lua",
	"tests/unit/character_system_test.lua",
	"tests/unit/sandbox_test.lua",
	"tests/unit/geometry_test.lua",
	"tests/unit/voxelise_test.lua",
	"tests/unit/compile_test.lua",
	"tests/unit/walk_grid_test.lua",
	"tests/unit/clip_test.lua",
	"tests/unit/buildings_render_test.lua",
	"tests/unit/serialize_test.lua",
	"tests/unit/scene_test.lua",
	"tests/unit/insert_test.lua",
	"tests/unit/properties_test.lua",
	"tests/unit/pick_test.lua",
	"tests/unit/transform_test.lua",
	"tests/unit/params_test.lua",
	"tests/unit/shape2d_test.lua",
	"tests/unit/work_plane_test.lua",
	"tests/unit/shape_tool_test.lua",
	"tests/unit/extrude_test.lua",
	"tests/unit/lathe_test.lua",
	"tests/unit/path_test.lua",
	"tests/unit/sweep_test.lua",
	"tests/unit/path_tool_test.lua",
	"tests/unit/palette_test.lua",
	"tests/unit/recent_colours_test.lua",
	"tests/unit/design_cache_test.lua",
	"tests/unit/prefab_test.lua",
	"tests/unit/text_buffer_test.lua",
}

local tests = {}
local failures = {}

local function valueToString(value)
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function fail(message)
	error(message, 2)
end

function test(name, fn)
	table.insert(tests, {
		name = name,
		fn = fn,
	})
end

function assertTrue(value, message)
	if not value then
		fail(message or "expected value to be truthy")
	end
end

function assertFalse(value, message)
	if value then
		fail(message or "expected value to be falsey")
	end
end

function assertEqual(expected, actual, message)
	if expected ~= actual then
		fail(message or string.format("expected %s, got %s", valueToString(expected), valueToString(actual)))
	end
end

function assertNear(expected, actual, tolerance, message)
	tolerance = tolerance or 0.000001
	if math.abs(expected - actual) > tolerance then
		fail(
			message
				or string.format(
					"expected %s to be within %s of %s",
					valueToString(actual),
					valueToString(tolerance),
					valueToString(expected)
				)
		)
	end
end

local function testFilesFromArgs()
	local files = {}
	for i = 1, #arg do
		table.insert(files, arg[i])
	end

	if #files == 0 then
		return defaultTestFiles
	end

	return files
end

local function loadTestFile(path)
	local chunk, err = loadfile(path)
	if not chunk then
		error(string.format("Could not load %s: %s", path, err))
	end
	chunk()
end

local function run()
	local files = testFilesFromArgs()

	for _, file in ipairs(files) do
		loadTestFile(file)
	end

	for _, case in ipairs(tests) do
		local ok, err = xpcall(case.fn, debug.traceback)
		if ok then
			print("✓ " .. case.name)
		else
			table.insert(failures, {
				name = case.name,
				error = err,
			})
			print("✗ " .. case.name)
			print(err)
		end
	end

	local passed = #tests - #failures
	print(string.format("\n%d passed, %d failed", passed, #failures))

	if #failures > 0 then
		os.exit(1)
	end
end

run()
