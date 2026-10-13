Status: done
Complexity: 5 (design 1, scope 2, tests 1, hazards 1)

# Place buildings in the world

## What to build
- Pick a design from the library in the world. A ghost sprite follows the cursor, and `R` cycles the 4 facings.
- The ghost shows valid or invalid: footprint clear of water, nodes and buildings; every port tile open; materials affordable.
- Placing pays the cost and creates a building with the design version, facing and empty buffers. Port tiles are marked in the world.

## Files to create/modify
- src/game/buildings/{placement,building}.lua, src/game/systems/building_system.lua
- src/game/session.lua (building pool)
- src/app/screens/world.lua (placement mode), src/app/render/{buildings,ghost}.lua
- tests/unit/placement_test.lua, tests/integration/place_building_test.lua

## Test approach
- Unit: footprint and port tiles for every facing of an asymmetric design. Each invalid reason. Cost deducted once.
- Integration: place a building, then check inventory, tile occupancy and that the character is blocked by it.

## Acceptance criteria
- [ ] A placed building draws its baked sprite for the chosen facing.
- [ ] Port tiles land on the correct sides in all 4 facings.
- [ ] Invalid placements are refused and say why.

## Blocked by
4, 9
