# ADR 0005: Views are data, baked per view

**Status:** Accepted
**Date:** 2026-10-20

## Context
- ADR 0001 fixed one 3/4 projection for the life of the art, so a new angle meant rebaking everything.
- Players want to choose between perspectives: 3/4 top-down, 2:1 isometric and true isometric, with more later.

## Decision
- A **view** is plain data in `config`: a ground matrix, a vertical lift per unit z and an affine depth.
- `src/game/projection.lua` builds every world-to-screen, screen-to-world, depth and sprite-frame function from the active view.
- The baker and all renderers take the view from `Projection`. Simulation, `ctx` and saves never learn the view.
- Sprites bake lazily per view. Prop atlases cache on disk with a view suffix, and 3/4 top-down keeps its current file names. Design sprites cache in memory keyed by view.
- The view is a player-level setting, saved outside the world save.
- Each view has one fixed orientation. There is no camera rotation.

## Alternatives Considered
- **Pre-bake all views at launch:** instant switching, but startup and cache grow with every view.
- **Hard-code each view in renderers:** simple for two views, but every new view touches every renderer.
- **Store the view in the world save:** a preference would then differ per world and need migration.

## Consequences
- The first switch to a new view bakes and may hitch. A repeat switch is instant.
- Disk cache grows by one atlas set per view used.
- Any code with inline projection math is a bug in an isometric view.
- Lift per unit z is rounded so `lift * tileSize / 16` stays whole and voxel heights land on whole pixels: 1.5 for 2:1 isometric (exact 1.265) and 1.0 for true isometric (exact 1.155). In true isometric a vertical face is about 13% smaller than the top face. Using the exact lift would equalise them and give up whole-pixel voxels.
- ADR 0001's "camera angle is fixed for the life of the art" no longer holds. Its other consequences stand.
