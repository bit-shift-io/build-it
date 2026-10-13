---
name: love-12-mesh-vertex-format
description: LÖVE 12 newMesh vertex formats need a `location` per attribute; custom attributes bind by `layout (location = N) in` in the shader
metadata:
  type: convention
---

**Why:** 11.x examples pass `{ {"VertexPosition", "float", 3}, ... }` or `{ name, format }` tables. On build `b7daef0f` that fails with `'location' field expected in array element #1 of format table`.
**How to apply:** Any `love.graphics.newMesh` with a custom vertex format, and any shader that reads a custom vertex attribute.

- Format entries: `{ name = "VertexPosition", format = "floatvec3", location = 0 }`.
- Verified locations: `VertexPosition` = 0, `VertexColor` = 2. Custom attributes use a free location (the baker uses 3 for `VertexNormal`).
- In the vertex shader, declare a custom attribute as `layout (location = 3) in vec3 VertexNormal;` and pass it on with `out`/`in` varyings.
- Example: `src/app/bake/baker.lua` and `src/app/bake/block_shader.glsl`.
