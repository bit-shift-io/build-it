---
name: builder-tool-keys-in-tests
description: Integration and e2e tests pick script-builder tools by tapping digit keys; changing ScriptBuilderScreen.TOOLS slot numbers breaks them
---

Builder tests pick a tool with `Fake.tap(game, "<digit>")` or `game:keypressed("<digit>")`, matching the slot in `ScriptBuilderScreen.TOOLS`.

**Why:** Renumbering `TOOLS` silently turns a tool pick into a different tool, or into a toggle-off.

**How to apply:** When `TOOLS` changes, grep `tests/integration` and `tests/e2e` for digit taps and remap the tool picks. Not every digit is a tool pick. The world-screen picker's "1", and digits typed into property or code text, stay as they are.
