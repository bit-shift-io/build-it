---
name: library-designs-shared-with-world
description: buildings and sites placed this session hold the library's own design tables; removing a version from design.versions crashes drawing and world save
metadata:
  type: context
---

**Why:** Placing a building stores the library design table itself in `b.design`, not a copy. `DesignCache` asserts `design.versions[n]` exists. The world save snapshots `b.design.versions[b.version]`. Removing or replacing a version in the library during a session breaks every building placed from it.
**How to apply:** Any code that changes `Library` designs in memory: deleting, renaming, compacting. Mark versions retired (`design.retired[n]`) instead of removing them. Buildings loaded from a world save are safe; they use the save's own design snapshot tables.
