# Build-it Architecture

Build-it uses gravity's **composed pools**: typed entity pools, plain-data components, and pool systems that call them.
The world is 2D; 3D exists only for the builder and the baker ([ADR 0001](adr/0001-2d-world-baked-block-sprites.md)).
It targets LÖVE 12 only ([ADR 0002](adr/0002-love-12-dev-build-only.md)).
Terms are defined in [CONTEXT.md](CONTEXT.md).

## Layers

Dependencies point down only. A module never requires a module from a layer above it.

| Layer | Path | Owns | May use `love.*` |
|---|---|---|---|
| app | `src/app/` | LÖVE callbacks, input mapping, camera, rendering | **Yes, the only layer that may** |
| game | `src/game/` | Session, world, pools, systems, components, tuning config | No |
| core | `src/core/` | vec2 math, seeded RNG | No |

- `game` and below run under plain LuaJIT with no `love` global. Unit tests exercise them without a mock.

## The two kinds of thing

### Pool record (game)
- A plain table in a typed pool, e.g. `ctx.pools.characters`.
- Holds its position plus component sub-tables.
- No metatables, no methods, no back-pointers.

### Component (game)
- A plain-data sub-table on a record, e.g. `character.mover`.
- Paired with a module of pure functions in `src/game/components/<name>.lua`.
- Functions take the record (or the sub-table) plus `ctx`, and return or mutate data.
- A component **never** has an `update` or `draw` that runs itself. The owning pool system calls it.

```lua
-- a character record
{ id = 1, player = 1, x = 1024, y = 1024, size = 16,
  mover = { speed = 160 } }
```

## Systems and frame order

- One system module per pool: `src/game/systems/<pool>_system.lua`.
- A system exposes `update(ctx)` and calls component functions **explicitly, in a visible order**:

```lua
function CharacterSystem.update(ctx)
  for _, c in ipairs(ctx.pools.characters) do
    Mover.apply(c, ctx.intents[c.player] or NO_INTENT, ctx)
  end
end
```

- The whole frame order lives in one function, `Session.step(ctx)`:
  1. Read player intents (from `ctx.intents`). `app` fills them before the step.
  2. Characters: walk.
  3. **Despawn sweep**, the only place records are removed (added once anything can be removed).
- Nothing is removed mid-iteration. Systems mark records `dead = true`; the sweep removes them.

## `ctx`

- One table passed to every system and component function.
- Holds `dt`, `time`, `world`, `config`, `seed`, `rng`, `intents`, `pools`.
- No module reads globals for game state.

## World

- A world is a literal table `{ width = <tiles>, height = <tiles> }`. Tile size in pixels is `config.tileSize`.
- `src/game/world.lua` answers geometry questions (pixel size, centre).

## Rendering

- `src/app/render/` holds one draw module per pool, plus the world.
- Draw modules read record data. They never mutate it.
- Components never draw themselves.
- `src/app/camera.lua` follows the player and zooms with the mouse wheel. Its follow and zoom math is pure; only `attach`/`detach` touch `love.graphics`.

## Adding things

- **New behaviour shared across types** → a new component module; add the sub-table in each record constructor that needs it; add one call in each owning system.
- **Optional component** → the system nil-checks: `if c.inventory then Inventory.tick(c, ctx) end`.
- **New entity type** → a new pool, a new system, a new render module, one new line in `Session.step`.

## Rules

- No `love.*` outside `src/app/`. Dev-only `tests/` and `tools/` may use it; they are never shipped.
- No classes or inheritance. Plain tables and function modules.
- No component self-updates. Systems call components.
- No removal outside the despawn sweep.
- All tuning numbers live in `src/game/config.lua`.
- Determinism: world generation and prop variants derive from seeds through `src/core/rng.lua`, never `math.random`.
- Fixed timestep of 1/60 s. `app` accumulates real time and calls `Session.advance` in fixed increments.
