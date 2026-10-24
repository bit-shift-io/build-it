# ADR 0008: Building collision comes from geometry

**Status:** Accepted
**Date:** 2026-10-24

## Context
- Footprints were solid tiles. Operators walked into their own building through its walls.
- The player and operators now walk inside buildings and through doors.
- Walls in designs are often one voxel thick, far below tile resolution.

## Decision
- Each blueprint carries a walk grid: stud cells (4 per tile side), blocked when voxels lie in the body-height band.
- Designs never tag walls or doors. A doorway is any open path from the footprint edge inward.
- Compile fails when a function brick or bed can't be reached from outside.
- The walk grid is saved with the blueprint. Save format 9 refuses older saves.
- Only the player and a building's own operator or sleeper walk inside. Haulers use port tiles.

## Alternatives Considered
- Explicit door and wall tags: precise, but every untagged design collides wrongly.
- Door tiles only, no interiors: operators couldn't move around their brick.
- Rebuilding the grid on load: saved blueprints hold a merged mesh, not the closed parts the voxeliser needs.

## Consequences
- Any geometry at body height blocks, decorative or not. Low geometry never blocks.
- Changing body height changes which designs compile and how they collide.
- Paths inside a footprint run at stud resolution; outside stays tile-level.
