Status: pending
Complexity: 2 (design 1, scope 1, tests 0, hazards 0)

# Aura traits

## What to build
- Bricks can contribute aura traits: walk speed and hand-harvest rate.
- While the character stands within a building's reach, those auras apply. Several auras stack additively.
- The HUD shows active aura bonuses.

## Files to create/modify
- src/game/components/aura.lua, src/game/builder/traits.lua, src/game/config.lua
- src/game/systems/character_system.lua, src/app/render/hud.lua
- tests/unit/aura_test.lua

## Test approach
- Unit: in-range and out-of-range checks, additive stacking, and the effect on mover speed and harvest cycle.

## Acceptance criteria
- [ ] Walking near a building with a speed aura makes the character faster, and leaving removes it.
- [ ] The builder sidebar shows aura totals.

## Blocked by
11
