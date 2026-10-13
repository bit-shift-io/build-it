Status: pending
Complexity: 6 (design 1, scope 2, tests 1, hazards 2)

# World save and load

## What to build
- One save slot: world seed, terrain changes, nodes (amount, stage, growth), buildings (design version, facing, buffers, storage, reservations), character and inventory.
- Autosave on quit, and manual save with F5. Launch offers Continue or New game.

## Files to create/modify
- src/game/save/codec.lua
- src/app/save_store.lua, src/app/screens/title.lua, src/app/flow.lua
- tests/unit/save_codec_test.lua, tests/integration/save_load_test.lua

## Test approach
- Unit: the codec round-trips a session. Loading then stepping matches stepping an unsaved copy (determinism check).
- Integration: play, save, reload and compare state.

## Acceptance criteria
- [ ] Quit and relaunch restores everything listed above.
- [ ] A building whose design version is missing from the library still loads and draws, from a version snapshot in the save.

## Blocked by
13, 14

## Gotchas
- Snapshot each referenced design version into the world save. The library can lose files, and a world must not depend on it.
- Persist rng state, or post-load world events diverge from the pre-save run.
