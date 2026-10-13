---
name: love-12-no-filesystem-rename
description: LÖVE 12's love.filesystem has no rename; atomic save-dir writes use os.rename on paths under getSaveDirectory()
metadata:
  type: convention
---

**Why:** Build `b7daef0f`'s `love.filesystem` lists no `rename` (probed: append, createDirectory, exists, getDirectoryItems, getInfo, read, remove, write, ... but no rename or move). Writing a file in place with `love.filesystem.write` leaves a half-written file if the game dies mid-write.
**How to apply:** Any save-directory file that must never be left half-written (the design library, later the world save).

- Write the text to `<path>.tmp` with `love.filesystem.write`, then `os.rename(save .. "/" .. tmp, save .. "/" .. path)` with `save = love.filesystem.getSaveDirectory()`. On macOS `rename(2)` replaces the target atomically. Verified on the pinned build: `os.rename` exists and moves files in the save directory.
- On a failed rename, remove the `.tmp` and keep the old file.
- Readers skip `*.tmp` leftovers.
- The integration tier's `tests/support/love_mock.lua` backs `love.filesystem` with a real temporary directory so this path runs for real.
- Example: `src/app/design_store.lua`.
