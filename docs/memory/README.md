# Repo Memory

Situational facts: true only when touching a particular area. One fact per file.

- [love-12-pinned-build.md](love-12-pinned-build.md) — run with `/Applications/love12.app` (build `b7daef0f`), never 11.5 on PATH; check graphics calls against the 12 API
- [test-framework-from-gravity.md](test-framework-from-gravity.md) — test tiers are ported from `~/Projects/gravity/tests`; what to keep, strip and adapt; register new test files
- [love-12-mesh-vertex-format.md](love-12-mesh-vertex-format.md) — `newMesh` vertex formats need a `location` per attribute; custom shader attributes bind by `layout (location = N) in`
- [love-12-depth-canvas.md](love-12-depth-canvas.md) — depth canvases on Metal: `depthstencil` canvas or `depth = true`; clip z stays GL-style [-1, 1], smaller is nearer with `"less"`
- [love-12-canvas-dpiscale.md](love-12-canvas-dpiscale.md) — `newCanvas` takes the window DPI scale; use `{ dpiscale = 1 }` for canvases that are read back, saved or used as atlases
- [love-12-no-filesystem-rename.md](love-12-no-filesystem-rename.md) — no `love.filesystem.rename`; atomic writes go to `.tmp`, then `os.rename` under `getSaveDirectory()`
- [e2e-isolate-save-dir.md](e2e-isolate-save-dir.md) — e2e shares the player's real save dir; give designs/save/prop-cache test-only names and clear them first
- [design-id-reuse.md](design-id-reuse.md) — losing the newest design file frees its id; caches keyed by design id+version can collide with world-save snapshots (unfixed)
- [library-designs-shared-with-world.md](library-designs-shared-with-world.md) — buildings placed this session hold the library's design tables; never remove a version from `design.versions` mid-session
- [world-screen-modal-input.md](world-screen-modal-input.md) — world-screen menus and text boxes must drop the opening key's textinput and suppress polled WASD/E/F intents
- [projection-single-source.md](projection-single-source.md) — world/screen pixel math goes through `Projection` with the active view; no inline `tileSize` math
