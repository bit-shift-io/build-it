# ADR 0007: Buildings freeze a blueprint; designs have no versions

**Status:** Accepted
**Date:** 2026-10-21

## Context
- Designs had immutable versions so placed buildings never changed underneath the colony.
- Prefabs are linked: editing the bed prefab must change every design that uses it.
- Linked prefabs and immutable versions can't both hold.

## Decision
- A design is one mutable file. There are no versions.
- Placing a design compiles it into a **blueprint**: mesh, footprint, roles, port tiles, cost and traits.
- Sites and buildings hold their blueprint. The world save stores it. Editing a design or prefab never changes a placed building.
- **Replace…** on a building turns it back into a site for any design. The site reserves only the missing materials.

## Alternatives Considered
- **Buildings follow edits live:** ports could move under haulers, a saw could vanish under its operator, and a site's reserved cost could change.
- **Designs pin prefab versions:** safe, but edits don't flow through, which defeats linked prefabs.

## Consequences
- World saves carry every blueprint's mesh, so they grow with design complexity.
- Sprites key on a blueprint's content hash, not on a design id and version.
- A design deleted from the library leaves its placed buildings working.
