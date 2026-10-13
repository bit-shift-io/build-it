Status: pending
Complexity: 6 (design 2, scope 2, tests 0, hazards 2)

# Function bricks, ports, storage, traits and cost

## What to build
- New bricks: saw, pickaxe, planter, saw bench (function bricks), input port, output port, storage brick. Each has its own model and cost.
- The sidebar shows live trait totals (productivity, capacity, reach, health) and total cost against the inventory. Cost includes the baseplate per tile.
- Validation messages for: no function brick, no output port, port not on the footprint edge at ground level, saw bench without an input port.

## Files to create/modify
- src/game/builder/{bricks,traits,cost,validate}.lua
- src/game/config.lua (costs, per-material traits, function brick definitions)
- src/app/screens/builder.lua (sidebar: traits, cost, errors)
- tests/unit/{traits,cost,validate}_test.lua

## Test approach
- Unit: trait sums per material mix. Cost sums with baseplate tiles. Each validation rule fires alone and passes when satisfied. A port's facing tile derives from its edge.

## Acceptance criteria
- [ ] Placing a stone brick visibly raises health and lowers productivity in the sidebar.
- [ ] Cost shows red where the inventory is short.
- [ ] Each invalid design shows the specific rule it breaks.
- [ ] Save in the builder is refused while the draft breaks a rule (slice 09 built save before validation existed and only requires at least one brick).

## Blocked by
7

## Gotchas
- A port on a corner stud touches two edges. Pick one facing deterministically (e.g. by brick rotation) and test it.
- Function bricks define abilities. Never key behaviour off the design name.
