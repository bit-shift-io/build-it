# Build-it Prototype

## Problem
- In a settlers-style RTS, buildings are fixed designs. The player only chooses where to put them.
- We want to test whether designing your own buildings from Lego-style bricks is fun.
- We also want to test whether brick choices that change how a building performs make design a real decision.

## Solution
- The player walks a 2D tile world and hand-harvests logs and stone.
- The player designs buildings in a 3D brick builder. Function bricks give a building its abilities, and brick materials give it traits.
- Saved designs bake to sprites. The player places them in the world, where they harvest, convert and store items.

## Out of Scope
- Decorative buildings with no function brick.
- Belts, inserters, carriers, roads. The player hand-carries all items between ports.
- Food chain (fisher, hunter, farm, mill, bakery, well), mines, metalwork.
- Building damage, combat, character health effects.
- Refunds, demolition, and upgrading placed buildings to a newer design version.
- Gamepad input. Multiple save slots. LÖVE 11.5 support.

## Cross-cutting Constraints
- **LÖVE 12 only**, pinned to dev build `b7daef0f`. See [ADR 0002](../../docs/adr/0002-love-12-dev-build-only.md).
- **2D world, 3D only for baking.** World simulation and rendering are 2D. Block models exist only in the builder and the baker. See [ADR 0001](../../docs/adr/0001-2d-world-baked-block-sprites.md).
- **Gravity's layering.** `core` → `game` → `app`, with dependencies pointing down only. No `love.*` outside `src/app/`. `game` and below run under plain LuaJIT.
- **Gravity's conventions.** Plain tables and function modules, no classes. Typed pools plus plain-data components called by pool systems. One `ctx`. One frame-order function. Removal only in a despawn sweep. Fixed 1/60 s timestep.
- **All tuning numbers live in `src/game/config.lua`**: brick costs, trait values per material, buffer sizes, cycle times, radii.
- **Determinism.** World generation and prop variants derive from seeds. The same seed always produces the same world and sprites.
- **One camera angle.** Every baked sprite uses the world's 3/4 top-down projection. The world camera and the baker share that projection, so they never diverge.

## Acceptance Criteria
- [ ] A new game generates a seeded world with trees, rocks and water, all drawn from baked block-model sprites.
- [ ] A voxel character walks in 8 directions with a walk cycle and hand-harvests logs and stone.
- [ ] The player designs a building with a saw, an output port and storage, sees trait totals and cost, and saves it.
- [ ] The player places the design in any of 4 facings, it harvests trees in parallel per saw, and the player collects logs from its output port.
- [ ] A sawmill design turns hand-delivered logs into planks. A forester design replants trees.
- [ ] A building's aura changes the character's walk speed or hand-harvest rate.
- [ ] Editing a placed design leaves existing buildings on their original version.
- [ ] Quitting and relaunching restores the world, buildings, inventory and design library.

## References
- [ADR 0001: 2D world with baked block-model sprites](../../docs/adr/0001-2d-world-baked-block-sprites.md)
- [ADR 0002: LÖVE 12 dev build only](../../docs/adr/0002-love-12-dev-build-only.md)
- [Glossary](../../docs/CONTEXT.md)
- Reference architecture: `/Users/fabian/Projects/gravity` (`docs/ARCHITECTURE.md`, `tests/`)
- Economy model: The Settlers II, first tier (woodcutter, forester, quarry, sawmill)
