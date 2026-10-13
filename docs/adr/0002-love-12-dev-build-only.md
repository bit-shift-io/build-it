# ADR 0002: LÖVE 12 dev build only

**Status:** Accepted
**Date:** 2026-10-13

## Context
- LÖVE 12 is unreleased. The latest official release is 11.5 (2023-12-03).
- The builder and baker need depth-buffered canvases, 3D vertex formats, instancing and custom shaders.
- LÖVE 12 improves exactly those APIs. They are also the APIs that changed most from 11.5.
- The sibling project gravity supports both versions through a compat layer. It only draws 2D primitives.

## Decision
- Target LÖVE 12 only.
- Pin the CI build from love2d/love `main` at commit `b7daef0f` (run 35517017483, 2026-09-20).
- Install it as `/Applications/love12.app`, beside 11.5. `run.sh` and the e2e runner point at it.
- Upgrade the pinned build deliberately, in its own change.

## Alternatives Considered
- **11.5 and 12 (gravity's approach):** a compat layer around every 3D and canvas call, the riskiest code in the project.
- **11.5 only:** older 3D API, and gravity's co-developer already runs 12.
- **Rust (Bevy) with Lua scripting:** see ADR 0001's context. It throws away gravity's architecture and test tiers.

## Consequences
- Players need a LÖVE 12 build until 12 ships. Fused releases must bundle it.
- API changes in later 12 builds can break us. The pin limits the blast radius.
- Most online LÖVE examples target 11.x. Check every graphics call against the 12 API.
