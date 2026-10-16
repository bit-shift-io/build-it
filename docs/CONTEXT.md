# Glossary

Domain terms for Build-it. Code, docs and conversation use these words with these meanings only.

# World and props

## Tile
- **Definition:** One cell of the 2D world grid.
- **Boundary:** Footprints, ports and resource nodes all align to tiles. One tile is 4×4 studs, or 16×16 voxels.

## Resource node
- **Definition:** A harvestable thing on a tile: a tree or a rock.
- **Boundary:** Holds a remaining amount and a stage. A depleted node disappears and frees its tile. Saplings are tree nodes not yet harvestable.

## Item
- **Definition:** A countable unit of a resource: log, stone or plank.
- **Boundary:** Items sit in an inventory, a buffer or storage. Logs are never a brick material.

## Inventory
- **Definition:** The items the player's character carries.
- **Boundary:** Unlimited. Placement doesn't pay from it. The player delivers it to a depot to make it spendable.

## Stockpile
- **Definition:** The planks and stone in the starting storage facility at the start of a new game.
- **Boundary:** It's a starting amount, not a building or place.

## Prop
- **Definition:** A world object drawn from a baked block model that isn't a building: tree, rock, sapling, stump.
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
- **Definition:** A brick that gives a building an ability: saw (harvest trees), pickaxe (harvest rocks), planter (plant saplings), saw bench (logs → planks).
- **Boundary:** Each one works independently and in parallel with the others, and only while an operator holds its operator job. The depot is the exception and needs no operator. Each costs resources. A design needs at least one to save.

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
- **Definition:** A building effect on the character or a villager while within the building's reach: walk speed, hand-harvest rate.
- **Boundary:** Auras from several buildings stack additively. They never affect other buildings.

## Design
- **Definition:** A named, player-made building plan: a baseplate and its bricks.
- **Boundary:** Belongs to the player, not a world. Saves even when unaffordable. The name is a label only, and abilities come from function bricks.

## Design version
- **Definition:** One immutable saved state of a design.
- **Boundary:** Editing a design creates a new version. A placed building keeps the version it was built from.

## Design library
- **Definition:** All of the player's designs, stored one file per design.
- **Boundary:** Shared across every world.

## Building
- **Definition:** A placed instance of a design version in the world, with a facing, buffers and storage contents.
- **Boundary:** It starts as a construction site and works once villagers build it. It can't be edited in place.

## Builder
- **Definition:** The 3D screen where the player designs and saves designs.
- **Boundary:** Designing is free. The builder never touches the world.

# Colony

## Villager
- **Definition:** A helper character that assigns itself to jobs. A new game starts with 20 around the starting storage facility.
- **Boundary:** Never controlled by the player. Holds one job at a time. Walks through building footprints, which the player can't.

## Job
- **Definition:** A unit of work one villager holds: an operator job, a haul job or a build job.
- **Boundary:** One villager per job. Free villagers take new jobs, nearest first. A busy villager is never pulled off a job.

## Operator job
- **Definition:** The job of running one function brick: harvesting, planting or converting, including carrying items in and out.
- **Boundary:** Sticky: the operator keeps it while the brick has work. Every function brick except the depot has one.

## Haul job
- **Definition:** One trip carrying a load from an output port or storage facility to an input port, a storage facility or a construction site.
- **Boundary:** Moves existing items only, never harvests. Ends after one trip.

## Build job
- **Definition:** The job of turning a construction site into a working building once all its materials are delivered.
- **Boundary:** Ends when the building is finished.

## Load
- **Definition:** The items a villager carries.
- **Boundary:** Capped by the carry limit in config. It's not an inventory.

## Depot
- **Definition:** A function brick that makes its building a storage facility.
- **Boundary:** Needs no operator. Its input port accepts every item.

## Storage facility
- **Definition:** A building with a depot. It holds the colony's items in its storage, and placement pays from it.
- **Boundary:** Capacity comes from its storage bricks and capacity trait. A new game starts with one, built from a built-in design. Items no building input accepts are hauled here.

## Construction site
- **Definition:** A placed design not yet built. Its cost is reserved in storage at placement.
- **Boundary:** Becomes a building once haulers deliver its cost and a build job finishes. Blocks its footprint like a building.
