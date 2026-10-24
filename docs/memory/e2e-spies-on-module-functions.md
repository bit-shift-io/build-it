---
name: e2e-spies-on-module-functions
description: e2e tests count calls by replacing module functions (e.g. `Baker.bake`); sending calls through a different function silently breaks them
metadata:
  type: convention
---

**Why:** Some e2e tests replace a module function with a pass-through counter, for example `tests/e2e/view_switch_test.lua` counting bakes. If the code starts calling a sibling function instead, such as `Baker.bakeTurned`, the counter stays at zero. The test then fails in the e2e tier, which slices often skip, while unit and integration tests stay green.
**How to apply:** When a change sends existing calls through a new or different function, especially in `src/app/bake/`.

- Grep the tests for replacements before finishing: `grep -rn '[A-Z][A-Za-z]*\.[a-zA-Z]* = function\|\[name\] = function' tests/`.
- Update each spy to count the new path too, or run the whole e2e tier rather than only the files the change touched.
