---
name: love-12-canvas-dpiscale
description: newCanvas defaults to the window's DPI scale; pass { dpiscale = 1 } for any canvas whose pixels are read back, saved or addressed by quads
metadata:
  type: convention
---

**Why:** `love.graphics.newCanvas(w, h)` takes the window's DPI scale, so on a Retina display it holds 2w x 2h pixels while `getWidth()` reports w. `readbackTexture`, a saved PNG and `newQuad` all work in pixels, so their coordinates stop matching the logical layout. An image loaded back from that PNG has dpiscale 1, so it would draw at twice the size.
**How to apply:** Any canvas that is read back, encoded to a file, or used as an atlas.

- Create it with `love.graphics.newCanvas(w, h, { dpiscale = 1 })`. Its pixel size and logical size are then the same, like an image loaded from a file.
- Drawing a default-DPI canvas (e.g. a `Baker.bake` sprite) into a dpiscale-1 canvas draws it at its logical size. Copy it with `setBlendMode("replace", "premultiplied")` to keep the baked pixels as they are.
- `love.graphics.readbackTexture(canvas):encode("png")` returns FileData. `love.filesystem.write(path, fileData)` writes it to the save directory, and `love.graphics.newImage(path)` loads it from there on a later launch.
- Example: `src/app/bake/prop_cache.lua`, and `renderFrame` in `tests/e2e/baker_test.lua`.
