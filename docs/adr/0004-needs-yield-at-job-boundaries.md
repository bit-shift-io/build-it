# ADR 0004: Needs yield at job boundaries

**Status:** Accepted
**Date:** 2026-10-17

## Context
- Villagers gain hunger and tiredness. Past a threshold they must eat or sleep.
- The job rule says a busy villager is never pulled off a job.
- Operator jobs are sticky and keep a villager while the brick has work. A strict rule would starve every operator.

## Decision
- A villager past the hungry or tired threshold is "in need". It takes no new job.
- A haul job or build job runs to its end as now.
- An operator job checks the need at the end of each cycle (`Operate.done`). In need, it finishes instead of starting the next cycle.
- The villager then eats or sleeps, and becomes free again.
- A villager is never pulled off mid-trip or mid-cycle.

## Alternatives Considered
- **Drop the job at once.** Rejected: half-done hauls leave loads and reservations to unwind.
- **Act only while free.** Rejected: sticky operators would never be free.

## Consequences
- Every job type has one place a need can end it. New job kinds must add one.
- A long build or a slow cycle delays a meal. Thresholds sit far enough below collapse to cover that.
- Undoing this means revisiting every job's end path and the pick tiers.
