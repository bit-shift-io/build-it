# ADR 0003: Function bricks need operators

**Status:** Accepted
**Date:** 2026-10-16

## Context
- Function bricks ran by themselves. A saw harvested trees in reach into its building, and a saw bench converted whatever reached its input.
- Villagers are being added: helpers that assign themselves to jobs.
- Villagers need meaningful work, and buildings had none to give.

## Decision
- Every function brick except the depot has one operator job. It does nothing without a villager holding that job.
- The operator does the physical work:
  - A saw or pickaxe operator harvests nodes in reach into their load, then carries it to an output port.
  - A planter operator carries a seed out and plants it.
  - A saw bench operator carries the input from an input port to the brick, waits a cycle, then carries the product to an output port.
- The brick's cycle time, raised by productivity, still sets the work time.
- The depot runs without an operator. Haulers deliver to it and collect from it.

## Alternatives Considered
- **Staff only converters.** Harvesters and planters stay automatic. Rejected because the planter's work is walking out to plant.
- **Operator stands at the building, and items move by themselves.** Rejected because the walking is the visible point of having villagers.

## Consequences
- Production now depends on villager count and walking distance. Building layout matters more.
- A world with too few villagers stalls. A new game starts with 20.
- Function brick code splits into a brick (cycle, reservation, "has work") and an operator job (walk, carry, wait).
- Undoing this means making bricks self-running again and rewriting every production test.
