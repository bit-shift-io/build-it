Status: pending
Complexity: 2 (design 0, scope 1, tests 1, hazards 0)

# Dev prop viewer

## What to build
- `love12 . props` opens a dev-only viewer that shows every variant and stage of a prop kind in a grid.
- `R` reloads generator source and rebakes without restarting. Arrow keys switch kind.

## Files to create/modify
- tools/prop_viewer/main.lua, main.lua (launch arg)
- tests/e2e/prop_viewer_test.lua

## Test approach
- E2e: open the viewer, capture the tree grid, and assert the sprite count equals variants × stages.

## Acceptance criteria
- [ ] All variants and stages of tree, rock, sapling and character display side by side.
- [ ] Editing a generator and pressing `R` shows the change.

## Blocked by
3
