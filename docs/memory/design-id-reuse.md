---
name: design-id-reuse
description: design ids are max existing + 1, so losing the newest design file frees its id; anything keyed by design id and version can collide with a world-save snapshot
metadata:
  type: context
---

**Why:** `Library` assigns the next design id as the highest loaded id + 1 (`"d" .. (max + 1)` in `src/game/designs/library.lua`). If the newest design file disappears, the next new design gets its id back. A world save still holds buildings from the old design, kept as a copy of its design version. `DesignCache` keys baked sprites by `<id>@v<n>@x<scale>`, so in one session the old building and the new design can share a cached sprite. Then one of them draws with the other's bricks.
**How to apply:** Any code that caches or looks up by design id and version: baking, placing buildings, world save and load. This also applies before adding anything else keyed that way.

- Known and unfixed as of 2026-10-16. Two possible fixes: store the highest id ever issued in the library so ids are never reused, or key the cache by the version's content (for example, a hash of its encoded bricks).
- Delete this entry once one of those fixes lands.
