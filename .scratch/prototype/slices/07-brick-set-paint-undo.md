Status: pending
Complexity: 5 (design 1, scope 2, tests 1, hazards 1)

# Builder: brick set, materials, paint, undo

## What to build
- A brick palette: 1×1, 1×2, 1×4, 2×2, 2×4 blocks and a slope. `R` rotates the held brick.
- Pick material (plank or stone, shown as texture) and paint colour (about 12-colour Lego palette, free).
- Undo and redo for place, remove and resize (Ctrl+Z / Ctrl+Shift+Z).

## Files to create/modify
- src/game/builder/{bricks,draft,history}.lua
- src/game/config.lua (brick shapes, palette)
- src/app/screens/builder.lua, src/app/render/builder_view.lua, src/app/bake/block_shader.glsl (material texture under paint)
- tests/unit/{bricks,history}_test.lua, tests/integration/builder_undo_test.lua

## Test approach
- Unit: rotated brick footprints. Undo/redo restores exact draft state across mixed operations, and a new action clears redo.
- Integration: place, paint, undo twice, redo once, and assert the draft.

## Acceptance criteria
- [ ] All brick shapes place and rotate correctly.
- [ ] Plank and stone bricks look different under any paint colour.
- [ ] Undo/redo covers every draft change.

## Blocked by
6
