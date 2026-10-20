---
name: projection-single-source
description: world/screen pixel math must go through Projection with the active view; inline x*tileSize math breaks isometric views
metadata:
  type: convention
---

**Why:** The 3/4 top-down view maps tile (x, y) to pixel (x*tileSize, y*tileSize), so code that did that inline worked. In an isometric view the ground is rotated, so inline math puts clicks, the camera and hover in the wrong place.
**How to apply:** Any code that turns a world position into a screen position, or the reverse (camera follow, hover, ghost, ports, status icons, terrain), calls `Projection` built from the active view. Do not multiply by `tileSize` yourself. Simulation positions (`x`, `y` in px) are world coordinates, not screen coordinates.
