Status: pending
Complexity: 5 (design 2, scope 1, tests 1, hazards 1)

# Voxel character

## What to build
- A character made of posed voxel parts (body, head, arms, legs). A pose is a set of part offsets and rotations.
- Bake 8 directions × (1 idle + 4 walk frames) through the baker at voxel scale.
- Replaces the placeholder. It faces its movement direction and animates while moving.

## Files to create/modify
- src/game/props/character.lua (parts, poses → block model per frame)
- src/game/components/animator.lua (frame from walk distance, direction from velocity)
- src/app/bake/prop_cache.lua (character frames in the atlas)
- src/app/render/character.lua
- tests/unit/{character_prop,animator}_test.lua, tests/e2e/character_render_test.lua

## Test approach
- Unit: each pose yields a block model with parts in the expected cells. 8-way direction mapping from velocity. Frame advances with distance, and idle when still.
- E2e: capture all 8 directions of walk frame 2 into one filmstrip.

## Acceptance criteria
- [ ] The character visibly faces 8 directions and animates a walk cycle.
- [ ] It stands still on the idle frame and keeps its last facing.
- [ ] Character frames are cached with the props and rebake on generator version change.

## Blocked by
3

## Gotchas
- Rotating parts on a voxel grid aliases. Prefer 90° limb swings plus offsets, or snap rotated cells to the grid deliberately.
