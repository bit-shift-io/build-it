---
name: e2e-isolate-save-dir
description: e2e tests share the real LÖVE save directory with the player's game; point every saved or cached folder at a test-only name and clear it first
metadata:
  type: convention
---

**Why:** e2e runs in a real LÖVE 12 window whose save directory is the player's real one (`~/Library/Application Support/LOVE/build-it`). A test using the default config reads or overwrites the player's designs, world save or prop cache, and its result depends on what happens to be there. One builder test already has to compare design counts before and after, because the real `designs` folder held designs.
**How to apply:** Any e2e test that saves, loads or bakes to disk: the design library, the world save or the prop cache.

- Give the test its own config table and set `config.designs.dir`, `config.save.file` and `config.props.cacheDir` to test-only names, such as `e2e_place_designs`.
- Clear those folders before the test runs, and clear the world save afterwards.
- Use a fresh config table when a test needs a cold design cache, because `BuildingsRender` keeps one `DesignCache` per config.
- The integration tier doesn't need this: `tests/support/love_mock.lua` backs `love.filesystem` with a temporary directory.
- Examples: `tests/e2e/world_save_test.lua`, `tests/e2e/place_building_test.lua`.
