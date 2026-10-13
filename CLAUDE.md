# Build-it

Factory-building game where you design buildings from Lego-style bricks and place them in a 2D tile world. LÖVE 12 (pinned dev build) + LuaJIT.

- Architecture and rules: `docs/ARCHITECTURE.md`. Layers `core` → `game` → `app`; no `love.*` outside `src/app/`.
- Glossary: `docs/CONTEXT.md`
- Decisions: `docs/adr/`
- Repo memory: `docs/memory/README.md`

## Running
- `./run.sh` runs the game on `/Applications/love12.app`. Never use `love` on PATH; that is 11.5 (`docs/memory/love-12-pinned-build.md`).

## Testing
- Unit tests: `sh test-unit.sh`. Run them freely.
- Integration: `sh test-integration.sh`. Headless, drives the real input path through `GameHarness` and `FakeInput`.
- E2e: `sh test-e2e.sh`. Opens a real LÖVE 12 window per test file and writes captures to `tests/screenshots/`. Run it once at the end of a piece of work, not per step.
- All tiers: `sh test-all.sh`. Reports each tier and skips e2e when `CI` is set.
- Put new tests in the unit tier unless the behaviour needs the real harness. `src/game` runs under plain LuaJIT, so `Session.new` and `Session.step` work there.
- The unit and integration runners use fixed file lists. Register every new test file in the tier's `run.lua`.

## Planning
- This project has no ClickUp card. Never ask about one and never offer to archive plans there.
