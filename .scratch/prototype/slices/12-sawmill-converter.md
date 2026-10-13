Status: pending
Complexity: 3 (design 1, scope 1, tests 0, hazards 1)

# Sawmill: input ports and conversion

## What to build
- The player stands on an input port tile and presses `E` to deliver logs, up to the buffer's free space.
- A saw bench function brick pulls 2 logs from inputs or storage and produces 1 plank to storage or outputs.
- Planks collected from the output enable building with plank bricks.

## Files to create/modify
- src/game/components/{function_brick,ports}.lua
- src/game/config.lua (recipe, cycle time)
- tests/unit/converter_test.lua, tests/integration/sawmill_test.lua

## Test approach
- Unit: the converter waits for 2 logs, consumes them, and outputs 1 plank. It stalls on a full output. Delivery caps at buffer space.
- Integration: deliver logs, wait, collect planks.

## Acceptance criteria
- [ ] A sawmill turns delivered logs into planks.
- [ ] Two saw benches convert in parallel.

## Blocked by
11

## Gotchas
- Input buffers accept only items some function brick in the building consumes. Reject other items at delivery.
