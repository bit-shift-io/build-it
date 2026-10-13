# Decisions

### Q1: 2D world or all-3D
**Decision:** 2D tile world. A 3D brick builder bakes designs to sprites.
- **Why:** Keeps Factorio-level density and cheap rendering. Factorio's own art is 3D pre-rendered to sprites.
- **Implication:** 3D code lives only in `src/app/` (builder view, baker). See ADR 0001.
- **Alternatives considered:** All-3D — loses density, adds camera and occlusion work and art cost.

### Q2: Engine
**Decision:** LÖVE, not Rust (Bevy + mlua).
- **Why:** Reuses gravity's architecture, test tiers and tooling. The 3D needed is boxes with one fixed camera.
- **Implication:** We write our own projection, depth and shader setup.
- **Alternatives considered:** Rust + 3D + Lua scripting — new engine and binding, and nothing the prototype needs.

### Q3: LÖVE version
**Decision:** LÖVE 12 only, pinned to CI build `b7daef0f` (2026-09-20).
- **Why:** 12 has better 3D: canvas depth formats, vertex formats, instancing, shader API.
- **Implication:** The build is unreleased, so the API may shift. Upgrade deliberately. See ADR 0002.
- **Alternatives considered:** 11.5 + 12 like gravity — a compat layer around exactly the calls that changed.

### Q4: What a placed building does
**Decision:** Buildings work. They harvest, convert and store items.
- **Why:** Traits only matter once they change something the player can see.
- **Alternatives considered:** Placement only — proves nothing about traits.

### Q5: What gives a building its abilities
**Decision:** Function bricks. Every function brick works independently and in parallel. Each costs resources.
- **Why:** Two saws should cut two trees at once. A saw plus a pickaxe cuts wood and mines stone.
- **Implication:** Output scales linearly with function bricks. Brick cost is the balancing lever. The design name is only a label.
- **Alternatives considered:** Role label picked at save; role plus required function brick. Both rejected for (b).

### Q6: Ports and storage
**Decision:** Input and output port bricks sit on the footprint edge at ground level. Each has a small buffer. Storage bricks add internal capacity. All cost resources.
- **Why:** Settlers/Factorio-style flow. Full outputs and storage stop the function bricks, which creates visible pressure.
- **Implication:** A design needs at least one output port. A converter function brick also needs an input port.

### Q7: Logistics
**Decision:** The player hand-carries items between ports.
- **Why:** Proves ports and buffers with no logistics system. Belts or carriers are each prototype-sized.

### Q8: Footprint
**Decision:** The player resizes the baseplate from 1×1 to 4×4 tiles. The baseplate costs resources per tile.
- **Implication:** 1 tile = 4×4 studs. Height cap is about 12 brick layers.
- **Alternatives considered:** Fixed footprint per role — irrelevant once roles come from function bricks.

### Q9: Economy scope
**Decision:** Settlers II first tier: Woodcutter (saw), Forester (planter), Quarry (pickaxe), Sawmill (saw bench: logs → planks).
- **Implication:** Brick materials are plank and stone only, never logs. The player starts with a stockpile of planks and stone.
- **Alternatives considered:** Adding a food building — deferred with the whole food chain.

### Q10: Traits
**Decision:** Productivity, capacity, reach, health. Each brick material contributes per brick. Building totals are sums.
- **Implication:** Health shows but does nothing yet. Reach sets both the harvest radius and the aura radius.
- **Alternatives considered:** "Speed" — dropped, since buildings don't move.

### Q11: Aura traits
**Decision:** A building boosts the character's walk speed and hand-harvest rate inside its aura radius. Auras stack additively.
- **Implication:** Character health waits until something can hurt the character.

### Q12: Persistence and design edits
**Decision:** The design library is per player, one file per design, and carries across worlds. The world has one save slot. Editing a design creates a new version, and placed buildings keep theirs.
- **Why:** One edit must never silently change the cost, footprint or ports of every placed building.
- **Alternatives considered:** Live blueprints that update every building — rejected.

### Q13: World and placement
**Decision:** Seeded procedural world of about 128×128 tiles with a 3/4 top-down camera. Buildings rotate in 4 facings, with 4 baked sprites per design version.
- **Implication:** Port tiles rotate with the building. A placement needs a clear footprint, open port tiles and the materials.

### Q14: Builder UX
**Decision:** Colour is free paint, separate from material. Material shows as texture. Mouse and keyboard only. Designs save even when unaffordable.
- **Implication:** Cost is paid only at placement.

### Q15: Props and character
**Decision:** Trees, rocks, saplings and the character are block models from Lua generator scripts, baked by the same baker.
- **Why:** One art pipeline and one consistent look.
- **Implication:** Props use 16×16 voxels per tile against 4×4 studs for buildings. About 8 seeded variants per prop kind, 3 harvest stages each. The character is posed parts baked in 8 directions with a walk cycle. A dev-only prop viewer helps tune generators.

## Key assumptions
- The character's inventory is unlimited in the prototype. Placement pays from it.
- Each function brick reserves its own resource node. Two saws never target the same tree.
- One function brick works one cycle at a time. Productivity shortens the cycle.
- Prop bakes cache in the save directory, keyed by generator version.
- Trees regrow only through foresters. Rocks never regrow.

## Trade-offs considered
- Hand-carry makes ports trivially convenient with an unlimited inventory. Accepted, since logistics comes later.
- Baking 4 facings per design version costs bake time on save. Accepted, since it only runs on save.
- Each prop kind gets 8 variants, against the atlas size. Tune the count in config.

## CONTEXT.md entries added
- Tile, Stud, Voxel, Block model, Baker, Facing, Prop, Prop generator, Variant, Stage, Resource node, Item, Inventory, Stockpile, Brick, Material, Function brick, Port, Buffer, Storage brick, Baseplate, Footprint, Trait, Aura, Design, Design version, Design library, Building, Builder.
