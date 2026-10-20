# Glossary

Domain terms for Build-it. Code, docs and conversation use these words with these meanings only.

# World and props

## Tile
- **Definition:** One cell of the 2D world grid.
- **Boundary:** Footprints, ports and resource nodes all align to tiles. One tile is 4×4 studs, or 16×16 voxels.

## Resource node
- **Definition:** A harvestable thing on a tile: a tree, a rock or a berry bush.
- **Boundary:** Holds a remaining amount and a stage. A depleted node disappears and frees its tile, except a berry bush, which refills. Saplings are tree nodes not yet harvestable. Water tiles and deer are not nodes.

## Item
- **Definition:** A countable unit of a resource: log, stone, plank, or a food (berry, meat, fish).
- **Boundary:** Items sit in an inventory, a buffer or storage. Logs are never a brick material.

## Inventory
- **Definition:** The items the player's character carries.
- **Boundary:** Unlimited. Placement doesn't pay from it. The player delivers it to a depot to make it spendable.

## Stockpile
- **Definition:** The planks, stone and berries in the starting storage facility at the start of a new game.
- **Boundary:** It's a starting amount, not a building or place.

## Prop
- **Definition:** A world object drawn from a baked block model that isn't a building: tree, rock, sapling, stump, berry bush, deer.
- **Boundary:** Props are made by the developer, never the player.

## Prop generator
- **Definition:** A Lua function `(rng, params) → block model` that builds one prop kind.
- **Boundary:** Pure and deterministic. Lives in `game`, never touches `love.*`. Carries a version number that invalidates cached bakes.

## Variant
- **Definition:** One seeded output of a prop generator.
- **Boundary:** Each prop kind has a fixed number of variants. A resource node picks a variant from the world seed.

## Stage
- **Definition:** A visual step of a resource node as it is harvested or grows: e.g. full, half-felled, stump.
- **Boundary:** Each stage is a separate baked sprite per variant.

# Blocks and baking

## Stud
- **Definition:** The grid unit of the builder. One tile is 4×4 studs.
- **Boundary:** Bricks snap to studs horizontally and to brick layers vertically.

## Voxel
- **Definition:** The grid unit of props and the character. One tile is 16×16 voxels.
- **Boundary:** Never used in the builder.

## Block model
- **Definition:** Plain data describing a 3D object as shaped cells (box, slope) on a grid, each with a colour and optional material.
- **Boundary:** The only input to the baker. Designs, props and character poses all become block models. Holds no rendering state.

## Baker
- **Definition:** The `app` module that renders a block model to a sprite through the world's 3/4 projection.
- **Boundary:** The only place block models become pixels in the world. The builder renders live, without baking.

## View
- **Definition:** The fixed perspective the world is drawn and baked in: 3/4 top-down, 2:1 isometric or true isometric.
- **Boundary:** Data in `config`, applied through the one projection. A sprite is baked per view. Changes drawing and picking only, never the simulation, saves or the builder.

## Settings
- **Definition:** Player-level preferences, saved in one file and shared by every world. Today only the view.
- **Boundary:** Never part of a world save.

## Facing
- **Definition:** One of 4 rotations of a building (N, E, S, W), or one of 8 directions of the character.
- **Boundary:** Each facing has its own baked sprite.

# Building design

## Brick
- **Definition:** A Lego-style piece placed in the builder: a shape, a material and a paint colour.
- **Boundary:** Plain bricks give traits. Function bricks, ports and storage bricks are bricks with extra roles.

## Material
- **Definition:** What a brick is made of: plank or stone.
- **Boundary:** Sets the brick's cost and traits. Shows as surface texture. It's not the same thing as paint colour, which is free and cosmetic.

## Function brick
- **Definition:** A brick that gives a building an ability: saw (harvest trees), pickaxe (harvest rocks), planter (plant saplings), saw bench (logs → planks), forager (harvest berry bushes), fishing brick (fish water), hunter (hunt deer), bed (sleep one villager), canteen (an eating spot).
- **Boundary:** Each one works independently and in parallel with the others, and only while an operator holds its operator job. The depot, bed and canteen are the exceptions and need no operator. Each costs resources. A design needs at least one to save.

## Port
- **Definition:** An input or output brick on the footprint edge at ground level. It faces one world tile, where the player delivers or collects items.
- **Boundary:** Each port has its own buffer. Port tiles rotate with the building's facing.

## Buffer
- **Definition:** The small item capacity of one port.
- **Boundary:** Capacity comes from config, raised by the capacity trait.

## Storage brick
- **Definition:** A brick that adds internal item capacity to a building.
- **Note:** A storage brick doesn't make a building a storage facility. A depot does.
- **Boundary:** Function bricks pull from input buffers and storage, and push to storage and output buffers.

## Baseplate
- **Definition:** The ground plate a design is built on. The player resizes it from 1×1 to 4×4 tiles.
- **Boundary:** Costs resources per tile. Its size is the footprint.

## Footprint
- **Definition:** The world tiles a building occupies.
- **Boundary:** Equals the baseplate size, rotated by facing.

## Trait
- **Definition:** A numeric building property summed from its bricks: productivity, capacity, reach, health.
- **Boundary:** Productivity shortens cycles. Capacity grows buffers and storage. Reach sets the harvest radius and aura radius. Health has no effect yet.

## Aura
- **Definition:** A building effect on the character or a villager while within the building's reach: walk speed and work rate.
- **Boundary:** Auras from several buildings stack additively. Work rate speeds the player's hand-harvesting and fishing, and every villager work cycle: operator cycles and building. It never speeds eating or sleeping. Auras never affect other buildings.

## Faced tile
- **Definition:** The tile next to the character in its facing direction, diagonals included.
- **Boundary:** E acts on it: a port tile delivers or collects, water catches fish. The tile underfoot wins over it.

## Design
- **Definition:** A named, player-made building plan: a baseplate and its bricks.
- **Boundary:** Belongs to the player, not a world. Saves even when unaffordable. The name is a label only, and abilities come from function bricks.

## Design version
- **Definition:** One immutable saved state of a design.
- **Boundary:** Editing a design creates a new version. A placed building keeps the version it was built from. Deleting a version retires its number for good.

## Design library
- **Definition:** All of the player's designs, stored one file per design.
- **Boundary:** Shared across every world. A design with no versions left is deleted, and its id is never reused.

## Building
- **Definition:** A placed instance of a design version in the world, with a facing, buffers and storage contents.
- **Boundary:** It starts as a construction site and works once villagers build it. It can't be edited in place.

## Building picker
- **Definition:** The world-screen list of every live design, with thumbnail, name and cost, that starts placement.
- **Boundary:** Opened from the context menu's Build entry or the 1 key. Scrolls and filters by name. It never edits designs; the builder does.

## Builder
- **Definition:** The 3D screen where the player designs and saves designs.
- **Boundary:** Designing is free. The builder never touches the world.

# Colony

## Villager
- **Definition:** A helper character that assigns itself to jobs. A new game starts with 20 around the starting storage facility.
- **Boundary:** Never controlled by the player. Holds one job at a time. Never enters a footprint, except the operator of a function brick entering that brick's building, or a sleeper entering its bed's building. Has a name and needs.

## Free villager
- **Definition:** A villager with no job. It idles at the linger spot of its last task, or in a gather area if it has none, until a job takes it.
- **Boundary:** Free villagers may carry a load. Idling never delays a job: the job takes the villager at once.

## Gather area
- **Definition:** The open ground within a set range of an anchor footprint, where free villagers idle. The anchor is the linger spot's building, else the nearest storage facility.
- **Boundary:** Free villagers never idle on a footprint or a port tile. They keep personal space and step aside for passers-by.

## Job
- **Definition:** A unit of work one villager holds: an operator job, a haul job, a build job, or a needs job (eat, sleep, feed).
- **Boundary:** One villager per job. A busy villager is never pulled off a job. A villager in need takes no new job, and an operator in need finishes at its cycle end (ADR 0004). A job goes first to a villager lingering on its task, then to free villagers not lingering, then to those lingering on other tasks. Within a group, nearest wins, with experience counting as nearness.

## Operator job
- **Definition:** The job of running one function brick: harvesting, planting or converting, including carrying items in and out.
- **Boundary:** Sticky: the operator keeps it while the brick has work, then lingers beside the building for the next one. Every function brick except the depot has one.

## Haul job
- **Definition:** One trip carrying a load from an output port or storage facility to an input port, a storage facility or a construction site.
- **Boundary:** Moves existing items only, never harvests. Ends after one trip. At a storage facility the hauler stands on a port tile: the input port to drop off, the output port to pick up. At a construction site it stands beside the footprint.

## Build job
- **Definition:** The job of turning a construction site into a working building once all its materials are delivered.
- **Boundary:** Ends when the building is finished. The builder works from beside the site, never inside it.

## Task
- **Definition:** What makes two jobs "the same" for lingering. Operator: the same function brick. Hauler: the same item, source building and destination building. Builder: any build job.
- **Boundary:** Not a job. A task outlives the job that set it.

## Linger spot
- **Definition:** Where a free villager waits after a job, as if it would get that task again. Operator: beside its building. Hauler: beside its route's source. Builder: beside the finished building.
- **Boundary:** Never expires. Taking any job clears it. Gone with its building; the villager then uses a storage facility's gather area. Not saved.

## Experience
- **Definition:** A villager's count of finished work per role: haul trips, builds, and operator cycles per brick ability.
- **Boundary:** Capped for picking, never decays, saved with the villager. Grants no perks yet.

## Load
- **Definition:** The items a villager carries.
- **Boundary:** Capped by the carry limit in config. It's not an inventory.

## Reservation
- **Definition:** Room or items held for one job so it can finish its trip.
- **Boundary:** A villager reserves drop-off room before it takes any item. Released on drop-off or when the job ends.

## Depot
- **Definition:** A function brick that makes its building a storage facility.
- **Boundary:** Needs no operator. Its input port accepts every item.

## Storage facility
- **Definition:** A building with a depot. It holds the colony's items in its storage, and placement pays from it.
- **Boundary:** Capacity comes from its storage bricks and capacity trait. Its fill is what its storage holds as a percentage of that capacity, ignoring port buffers. A new game starts with one, built from a built-in design. Items no building input accepts are hauled here. Haulers use its port tiles, never its footprint, so one with no ports is skipped.

## Construction site
- **Definition:** A placed design not yet built. Its cost is reserved in storage at placement.
- **Boundary:** Becomes a building once haulers deliver its cost and a build job finishes. Blocks its footprint like a building.

# Needs and food

## Name
- **Definition:** A villager's or the player's display name.
- **Boundary:** Drawn from a fixed list at spawn and saved. A label only.

## Need
- **Definition:** One of a villager's or the player's three meters: health, hunger, tiredness.
- **Boundary:** "In need" means past the hungry or tired threshold. A villager in need eats or sleeps before taking work.

## Health
- **Definition:** How close a villager or the player is to collapse.
- **Boundary:** Drains at full hunger. Regenerates while hunger is below the starving threshold. Unrelated to the health trait.

## Hunger
- **Definition:** A need that rises over time and falls when eating.
- **Boundary:** Hungry threshold triggers eating. Full hunger drains health.

## Tiredness
- **Definition:** A need that rises while awake and falls while asleep.
- **Boundary:** Villagers only; the player's stays at 0. Falls faster in a bed than on the ground.

## Collapse
- **Definition:** The state at 0 health.
- **Boundary:** A collapsed villager can't move or work, and gets up once fed. A collapsed player respawns at the nearest storage facility with its inventory. Nobody dies for good.

## Food
- **Definition:** An item that fills hunger: berry, meat or fish.
- **Boundary:** Each food has its own fill. Food never spoils. There is no cooking.

## Meal
- **Definition:** One sitting of eating.
- **Boundary:** Eats one item at a time, highest fill first, until hunger reaches 0. Villagers eat at a canteen or storage facility; the player from inventory or a storage facility in range.

## Feed job
- **Definition:** A job carrying food to a collapsed villager.
- **Boundary:** Goes before every other job. One feeder per collapsed villager.

## Bed
- **Definition:** A function brick that sleeps one villager.
- **Boundary:** Needs no operator. Not owned. A tired villager with no free bed sleeps where it stands, more slowly.

## Canteen
- **Definition:** A function brick that makes its building an eating spot.
- **Boundary:** Needs no operator. Haulers stock its input buffers with food. It doesn't cook.

## Forager
- **Definition:** A function brick whose operator picks berry bushes in reach.

## Fishing brick
- **Definition:** A function brick whose operator fishes water tiles in reach from the shore.
- **Boundary:** Water never runs out of fish.

## Hunter
- **Definition:** A function brick whose operator kills a deer in reach and carries back its meat.

## Berry bush
- **Definition:** A resource node that yields berries.
- **Boundary:** Picked clean, it refills over time and never vanishes.

## Deer
- **Definition:** A wandering animal, hunted for meat.
- **Boundary:** Lives in its own pool, not a node. Never flees. Belongs to one herd.

## Herd
- **Definition:** A group of deer sharing a home spot they wander near.
- **Boundary:** Grows by breeding up to a cap.
