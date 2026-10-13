---
name: love-12-pinned-build
description: Run with /Applications/love12.app (dev build b7daef0f); never fall back to the 11.5 `love` on PATH; check graphics calls against the 12 API
metadata:
  type: convention
---

**Why:** `love` on PATH is 11.5, kept for gravity. Running this project on it fails on 12-only graphics calls. Most online examples are 11.x and use removed APIs.
**How to apply:** When writing launch scripts or test runners, or any `love.graphics` canvas, mesh, shader or depth call.

- Binary: `/Applications/love12.app/Contents/MacOS/love` reports `LOVE 12.0 (Bestest Friend)`.
- Source: love2d/love GitHub Actions run 35517017483, artifact `love-macos`, commit `b7daef0f`.
- Install: unzip, rename to `love12.app`, move to `/Applications`. If Gatekeeper blocks it, run `xattr -dr com.apple.quarantine`.
- Avoid 11.x APIs: `setStencilTest`/`stencil` (use `setStencilState`), old `newCanvas` format options, old `newMesh` vertex-format tables.
