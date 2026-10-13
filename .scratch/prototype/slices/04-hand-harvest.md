Status: pending
Complexity: 4 (design 1, scope 2, tests 1, hazards 0)

# Hand harvesting and inventory

## What to build
- The character harvests an adjacent tree or rock with `E` or a click. A harvest cycle yields 1 log or 1 stone into the inventory.
- Nodes deplete through their stages: trees end as stumps, and rocks vanish.
- A HUD shows the inventory. A new game starts with the stockpile of planks and stone.

## Files to create/modify
- src/game/components/{harvestable,inventory}.lua
- src/game/systems/{character_system,node_system}.lua
- src/game/session.lua (despawn sweep for depleted rocks)
- src/game/config.lua (hand-harvest cycle, node amounts, stockpile)
- src/app/render/hud.lua, src/app/input.lua
- tests/unit/{harvestable,inventory}_test.lua, tests/integration/hand_harvest_test.lua

## Test approach
- Unit: harvest cycles take the configured time, add items, and advance stage at thresholds. A depleted rock is marked dead.
- Integration: walk to a tree, hold harvest, and check the log count and stump stage.

## Acceptance criteria
- [ ] Harvesting a tree adds logs and visibly steps it down to a stump.
- [ ] Harvesting a rock adds stone, and the rock disappears when empty.
- [ ] HUD shows logs, stone and planks. A new game starts with the configured stockpile.

## Blocked by
3
