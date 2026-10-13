Status: done
Complexity: 6 (design 1, scope 2, tests 1, hazards 2)

# Seeded world and baked props

## What to build
- A seeded 128×128 world: grass, water blobs as blockers, clusters of tree and rock resource nodes.
- Tree and rock prop generators (`(rng, params) → block model`) at 16×16 voxels per tile, 8 variants each, 3 stages each.
- Props bake once into an atlas cached in the save directory, keyed by generator version. Trees and rocks draw from it. Water blocks the character.

## Files to create/modify
- src/game/world_gen.lua, src/game/world.lua (terrain, node pool)
- src/game/props/{tree,rock,registry}.lua
- src/game/config.lua (world size, cluster params, variant count)
- src/app/bake/prop_cache.lua (atlas + cache file + version check)
- src/app/render/{terrain,nodes}.lua
- tests/unit/{world_gen,tree_prop,rock_prop}_test.lua, tests/integration/water_blocks_test.lua, tests/e2e/world_render_test.lua

## Test approach
- Unit: the same seed gives an identical world and identical prop models. Different seeds differ. Every node sits on grass. Stages shrink the model.
- Integration: walking into water stops the character.
- E2e: capture a seeded world region and check the cache file exists after the first run.

## Acceptance criteria
- [ ] A new game with a given seed shows the same forest and rocks every launch.
- [ ] Trees and rocks visibly vary across variants.
- [ ] A second launch skips prop baking. Bumping a generator version rebakes that kind only.
- [ ] The character can't walk on water or through nodes.

## Blocked by
2

## Gotchas
- Seed the prop rng per (kind, variant), never from a shared stream. Adding a kind must not reshuffle other kinds' variants.
- The mesher must face-cull at 16³ per tile, or bake time balloons.
