Status: pending
Complexity: 7 (design 2, scope 2, tests 2, hazards 1)

# Builder: place and remove bricks

## What to build
- `B` opens the builder screen: a live 3D view of a baseplate on the stud grid. Right-drag orbits, and the wheel zooms.
- Left-click places a 2×2 brick snapped onto the surface under the cursor. Right-click removes the brick under the cursor.
- Sidebar controls resize the baseplate from 1×1 to 4×4 tiles. `Esc` returns to the world.

## Files to create/modify
- src/game/builder/draft.lua (design draft: baseplate size, bricks; place/remove with collision and bounds checks)
- src/game/builder/pick.lua (ray vs stud grid and brick tops → placement cell)
- src/app/screens/builder.lua, src/app/render/builder_view.lua (live mesh, orbit camera)
- src/app/flow.lua (world ↔ builder screen switch)
- tests/unit/{draft,pick}_test.lua, tests/integration/builder_flow_test.lua, tests/e2e/builder_render_test.lua

## Test approach
- Unit: placement rejects overlap, out-of-baseplate and above-height-cap bricks. Pick returns the right cell for rays hitting the baseplate, a brick top or a brick side.
- Integration: open builder, place 3 bricks with fake mouse input, remove 1, and leave.
- E2e: capture the builder with a small stack.

## Acceptance criteria
- [ ] Bricks stack on the baseplate and on each other, snapping to studs.
- [ ] Shrinking the baseplate is refused while bricks sit outside the new size.
- [ ] The camera orbits and zooms without clipping the model.

## Blocked by
2

## Gotchas
- Keep ray-picking maths in `game` (pure), and pass it the camera matrices from `app`. That keeps picking unit-testable.
- The builder renders the live mesh. It never calls the baker.
