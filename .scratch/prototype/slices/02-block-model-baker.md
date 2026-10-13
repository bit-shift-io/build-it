Status: done
Complexity: 8 (design 2, scope 2, tests 2, hazards 2)

# Block model and baker

## What to build
- A block model data format: a grid scale plus shaped cells (box, slope) with colour and optional material.
- A pure mesher that turns a block model into face-culled triangles with normals. Hidden faces are dropped.
- An `app` baker that renders a block model through the shared 3/4 projection to a transparent sprite, at any of 4 facings. A hard-coded test model shows in the world.

## Files to create/modify
- src/game/blocks/model.lua (construct, add cell, bounds, rotate by facing)
- src/game/blocks/mesher.lua (cells → vertex list, face culling)
- src/game/projection.lua (the one 3/4 projection: world ↔ screen, model ↔ sprite)
- src/app/bake/baker.lua, src/app/bake/block_shader.glsl
- src/app/render/world.lua (draw a baked sprite at a tile, sorted by depth)
- tests/unit/{block_model,mesher,projection}_test.lua, tests/e2e/baker_test.lua

## Test approach
- Unit: two adjacent boxes share no internal faces. A slope emits the right triangle count. Rotating by facing maps cells correctly. Projection round-trips.
- E2e: bake a known model, then check sprite size, a transparent background, and a lit top face brighter than its side face. Capture it for eyeballing.

## Acceptance criteria
- [ ] A test house model bakes to a sprite in 4 facings and draws on the grid at the right tile.
- [ ] Sprites have a depth-tested interior (no back faces showing) and transparent edges.
- [ ] Sprite anchor puts the model's footprint exactly on its tiles at every zoom.
- [ ] Projection is defined once and used by both world rendering and the baker.

## Blocked by
1

## Gotchas
- This slice retires the LÖVE 12 3D risk. Spike the canvas + depth format + shader first, before the mesher's polish.
- Use 12's canvas depth formats and vertex-format API, not 11.x examples (`docs/memory/love-12-pinned-build.md`).
- Bake at an integer scale per world zoom level, or sprites blur. Decide the base pixels per tile here and put it in config.
- Write any 12 API surprises to `docs/memory/`.
