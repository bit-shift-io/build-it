# ADR 0001: 2D world with baked block-model sprites

**Status:** Accepted (the fixed-angle consequence is relaxed by [ADR 0005](0005-views-are-data-baked-per-view.md))
**Date:** 2026-10-13

## Context
- Players design buildings in 3D from Lego-style bricks, then place them in the world.
- We want Factorio-level detail and density in the world view.
- Factorio gets that density from 2D sprites pre-rendered from 3D models.

## Decision
- The world is a 2D tile grid. Simulation and world rendering are 2D.
- Everything visual in the world is a **block model** rendered once by the **baker** to a sprite. That covers player designs, props (trees, rocks) and the character.
- The baker and the world camera share one 3/4 top-down projection.
- Designs bake 4 facings per design version. The character bakes 8 directions per animation frame. Props bake several seeded variants per stage.
- 3D code exists only in `src/app/` (builder view, baker). `game` holds block models as plain data.

## Alternatives Considered
- **All-3D world:** loses density, adds camera control, occlusion and terrain art. A larger build for a prototype.
- **Hand-drawn 2D art:** can't show player-made designs.

## Consequences
- World rendering is sprite batching. Thousands of buildings stay cheap.
- The camera angle is fixed for the life of the art. Changing it means rebaking everything.
- No smooth rotation, and no camera orbit in the world.
- Bake time lands on design save and first launch. Prop bakes cache in the save directory.
- Animated buildings need extra baked frames per facing. None are planned yet.
