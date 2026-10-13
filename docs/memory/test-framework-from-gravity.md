---
name: test-framework-from-gravity
description: Test tiers are ported from ~/Projects/gravity/tests; copy from there, strip gravity's sim, match and Steam parts
metadata:
  type: convention
---

**Why:** Gravity's tiers already work headless under LuaJIT and headed under real LÖVE. Rewriting them wastes a slice and loses the capture tooling.
**How to apply:** When creating or changing anything under `tests/` or the `test-*.sh` scripts.

- Source: `/Users/fabian/Projects/gravity/tests/{unit,integration,e2e}/run.lua`, `tests/support/{frame_stepper,fake_input,capture,love_mock,game_harness}.lua`, `test-{unit,integration,e2e,all}.sh`.
- Keep: tier split, `test()`/`assert*` surface, `FrameStepper`, `FakeInput`, `Capture`, e2e `--paced` / `--filmstrip[=N]`, `CI` skip of e2e.
- Strip: matches, rounds, rosters, AI, Steam and trailer tests.
- Adapt: `GameHarness.startMatch(level)` becomes `GameHarness.startSession(worldTable, opts)`. Tests pass literal world tables.
- Point the e2e runner at the LÖVE 12 binary (see [[love-12-pinned-build]]).
- The unit and integration runners use fixed file lists. Register every new test file or it never runs.
