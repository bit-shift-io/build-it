# ADR 0006: Designs are sandboxed Lua scripts

**Status:** Accepted
**Date:** 2026-10-21

## Context
- The brick builder made every design a list of stud-aligned bricks. Building with it was not fun.
- Players want curves, sweeps and parametric parts, and want to share designs or write them with an LLM.
- A design file the player can read and edit must not be able to harm their machine.

## Decision
- A **design script** is a Lua file that describes a node tree, like an SVG describes shapes.
- `UI.*` calls at the top of a script declare **params**. The builder shows an input for each one.
- Scripts run in a sandbox: a fixed API, no `require`, `io`, `os`, `load`, `debug`, `string.dump` or `setfenv`, and an instruction budget.
- A script reaches other files only through `prefab("name")` and `design("name")`, looked up by name in the library. Paths are never accepted. A reference cycle is a load error.
- Designs and prefabs share the format and live in two folders.
- The builder owns **declarative** scripts: one node call per object with a stable id. It edits the tree and regenerates the whole file.
- A script with code the builder can't regenerate (loops, functions, maths) is **locked**: its objects are editable only through params and the code panel.
- Cost and traits come from voxelising the compiled mesh, never from analytic volume.

## Alternatives Considered
- **Data file (JSON or line records):** safe and easy to round-trip, but no procedural parts and nothing for an LLM to write code against.
- **Surgical source patching:** keeps hand-written comments and code editable from the GUI. It needs a Lua parser with source positions, and computed values still can't be patched.
- **Override layer on untouched scripts:** like Blender modifiers. Two sources of truth for one object.
- **Analytic volume from the operation tree:** exact, but overlaps and sweeps make it fragile.

## Consequences
- The design library, the world save and the starter building all change format. Old designs and saves are dropped.
- A hand-edited declarative file loses its comments and formatting on the next GUI save.
- The sandbox is a security boundary. Every new API function is a review point.
- Voxel cost is coarse at 16 voxels per tile. Thin parts can cost nothing.
