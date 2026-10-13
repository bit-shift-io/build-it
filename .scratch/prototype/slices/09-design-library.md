Status: done
Complexity: 5 (design 1, scope 2, tests 1, hazards 1)

# Design library and versions

## What to build
- Save a valid draft as a named design, even when unaffordable. Saving creates a new design version and bakes its 4 facings.
- The library persists one file per design (all versions) in the save directory, shared across worlds.
- Open an existing design in the builder to edit it. Saving appends a version.

## Files to create/modify
- src/game/designs/{library,codec}.lua (versions, serialise/parse)
- src/app/design_store.lua (filesystem I/O), src/app/bake/design_cache.lua
- src/app/screens/builder.lua (name, save, open)
- tests/unit/{design_library,design_codec}_test.lua, tests/integration/design_save_test.lua

## Test approach
- Unit: codec round-trips a design. Saving appends a version and never mutates older ones. A corrupt file is reported, not fatal.
- Integration: save, edit, save again, reload the library, and check 2 versions.

## Acceptance criteria
- [ ] Saved designs survive a relaunch.
- [ ] Editing and saving keeps the old version intact.
- [ ] Each version has 4 baked facings available to the world.

## Blocked by
7

## Gotchas
- Write files atomically (temp then rename) so a crash mid-save never corrupts the library.
