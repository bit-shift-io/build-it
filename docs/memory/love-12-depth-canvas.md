---
name: love-12-depth-canvas
description: LÖVE 12 depth-tested canvas rendering on macOS runs on Metal; clip z is still GL-style [-1, 1], smaller z is nearer with "less"
metadata:
  type: convention
---

**Why:** `love.graphics.getRendererInfo()` reports `Metal` on this Mac, whose native clip z is [0, 1]. LÖVE 12 remaps it, so shaders must keep writing GL-style z. Getting the direction or range wrong silently draws nothing or the wrong face.
**How to apply:** Any shader that sets `gl_Position.z` / the `position()` return z, or any `setDepthMode` call.

- Depth target: `love.graphics.newCanvas(w, h, { format = "depth24" })` passed as `setCanvas({ colorCanvas, depthstencil = depthCanvas })`. `setCanvas({ colorCanvas, depth = true })` also works (temporary depth buffer). `depth16`, `depth24`, `depth32f` and `depth24stencil8` are all supported.
- `love.graphics.clear(r, g, b, a)` on such a canvas also clears depth to the far value.
- Clip z in [-1, 1] is kept; z = -0.5 renders, z = 1.5 clips. With `setDepthMode("less", true)`, the smaller z wins regardless of draw order. `"greater"` after a clear draws nothing.
- With the default ortho transform, canvas pixel (0, 0) is the top-left of `readbackTexture`.
- Example: `src/app/bake/baker.lua`.
