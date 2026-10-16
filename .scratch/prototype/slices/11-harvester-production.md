Status: done
Complexity: 7 (design 2, scope 2, tests 1, hazards 2)

# Harvesting buildings and output ports

## What to build
- Each saw or pickaxe in a building independently reserves a node within reach and runs harvest cycles, in parallel.
- Output goes to storage, then output buffers. Function bricks stop when nothing has room, and resume when space frees.
- The player stands on an output port tile and presses `E` to take its items. Productivity shortens cycles, and capacity grows buffers and storage.

## Files to create/modify
- src/game/components/{function_brick,ports,storage}.lua
- src/game/systems/building_system.lua, src/game/systems/node_system.lua (reservations)
- src/app/render/buildings.lua (work indicators, port fill), src/app/render/hud.lua
- tests/unit/{function_brick,ports,storage,reservation}_test.lua, tests/integration/woodcutter_test.lua

## Test approach
- Unit: two saws harvest two different trees at once. A full output stalls the cycle. Productivity scales cycle time. Reservations release on depletion and on building removal.
- Integration: a woodcutter beside a forest fills its output; the player collects logs.

## Acceptance criteria
- [ ] A 2-saw woodcutter yields logs at twice the rate of a 1-saw woodcutter.
- [ ] A saw + pickaxe building yields both logs and stone.
- [ ] A building stops when full and visibly shows it.

## Blocked by
10

## Gotchas
- Order inside the step: release reservations for dead nodes before function bricks pick new targets. Otherwise a brick can grab a node being swept.
