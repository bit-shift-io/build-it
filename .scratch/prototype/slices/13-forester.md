Status: pending
Complexity: 4 (design 1, scope 1, tests 1, hazards 1)

# Forester

## What to build
- A planter function brick plants a sapling on a free grass tile within reach, one per cycle.
- Saplings grow through stages into full trees over time, and only become harvestable when full.
- Sapling and growth stages bake from the tree generator.

## Files to create/modify
- src/game/components/function_brick.lua (planter)
- src/game/props/tree.lua (growth stages), src/game/systems/node_system.lua (growth)
- src/game/config.lua (growth time, plant cycle)
- tests/unit/{planter,growth}_test.lua, tests/integration/forester_test.lua

## Test approach
- Unit: the planter picks only free grass tiles in reach and never blocks port tiles. Growth advances stages on time.
- Integration: run a forester for N simulated minutes and check grown trees appear.

## Acceptance criteria
- [ ] Foresters replant nearby, and woodcutters can harvest the grown trees.
- [ ] Saplings never spawn on footprints, port tiles, water or other nodes.

## Blocked by
11

## Gotchas
- Simulated time is long. Use a config override for growth time in tests, not real minutes.
