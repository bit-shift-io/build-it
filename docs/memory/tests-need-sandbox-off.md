---
name: tests-need-sandbox-off
description: integration and e2e tests fail inside the Claude Code sandbox; run them with it disabled
metadata:
  type: convention
---

**Why:** `tests/support/love_mock.lua` calls `os.tmpname()`, which writes to `/tmp`. The sandbox blocks that, and nearly every integration test fails with "unable to generate a unique filename". This is not a code failure. E2e has to launch the LÖVE 12 app, which the sandbox also blocks.
**How to apply:** When an agent runs `sh test-integration.sh`, `sh test-e2e.sh` or a single e2e file.

- Unit tests (`sh test-unit.sh`) run fine inside the sandbox.
- If integration shows mass failures, grep the output for `unique filename` before debugging. If it appears, re-run with the sandbox disabled.
