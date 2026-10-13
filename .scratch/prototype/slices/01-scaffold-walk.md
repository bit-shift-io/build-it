Status: pending
Complexity: 6 (design 1, scope 2, tests 2, hazards 1)

# Scaffold and walk a placeholder character

## What to build
- A LÖVE 12 project with gravity's layering (`core` → `game` → `app`) and its three test tiers.
- A flat tile world: the character is a placeholder square, moves with WASD, and the camera follows and zooms with the wheel.
- A fixed 1/60 s timestep driving `Session.step(ctx)`, the single frame-order function.

## Files to create/modify
- main.lua, conf.lua (LÖVE 12 only, identity `build-it`), run.sh, .luarc.json, .gitignore
- CLAUDE.md, docs/ARCHITECTURE.md (adapted from gravity's)
- src/core/{vec2,rng}.lua
- src/game/{config,session,world}.lua, src/game/systems/character_system.lua, src/game/components/mover.lua
- src/app/{main,camera,input,screen}.lua, src/app/render/{world,character}.lua
- test-{unit,integration,e2e,all}.sh, tests/{unit,integration,e2e}/run.lua, tests/support/*
- tests/unit/{rng,vec2,mover,session}_test.lua, tests/integration/walk_test.lua, tests/e2e/harness_smoke_test.lua

## Test approach
- Unit: `Session.step` with scripted intents moves the character the expected distance per step. The world edge clamps it.
- Integration: `GameHarness.startSession` plus `FakeInput` WASD moves the character over N frames.
- E2e: boots on LÖVE 12 and captures a frame showing grid and character.

## Acceptance criteria
- [ ] `./run.sh` opens a window on LÖVE 12 with a tile grid and a movable character.
- [ ] All three tiers run green, and `test-all.sh` reports each tier.
- [ ] `src/game` and `src/core` have no `love.*` references (unit runner has no `love` global).
- [ ] CLAUDE.md links ARCHITECTURE, CONTEXT, ADRs and repo memory.

## Blocked by
None — can start immediately.

## Gotchas
- Port the test framework per `docs/memory/test-framework-from-gravity.md`.
- `run.sh` and `test-e2e.sh` must use `/Applications/love12.app/Contents/MacOS/love`, not `love` on PATH (`docs/memory/love-12-pinned-build.md`).
- Drop gravity's 11.5 compat file and the `t.graphics = t.graphics or {}` guard rationale. This is 12-only.
