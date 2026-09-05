# World Semantics Audit

## Contract

`WorldSemantics` answers objective questions about a map location or boundary.
It does not decide whether an entity wants a feature, whether a species can use
an unavailable traversal mode, or which route reaches a destination.

The ownership chain is:

```text
Gen1Recomp public snapshot and registries
  -> SemanticSource (raw provenance)
  -> WorldSemantics (cell, context, edge, transition meaning)
  -> TraversalEvaluator (current actor legality)
  -> NavigationPlanner (route)
  -> behavior / needs / species ecology (desire)
```

Semantic snapshots and their caches are transient. They never enter persistent
entity records or `mod.storage`.

## Engine Inventory

The implementation is grounded in the current Gen1Recomp public Mod API and
source representation:

| Fact | Source representation | Semantic use |
| --- | --- | --- |
| Coarse collision | `mod.world:mapOverview().rows` | walkable, water, warp, blocked |
| Map definition | `mod.content.maps:get(mapId)` | dimensions, block IDs, tileset ID |
| Tileset definition | `mod.content.tilesets:get(tilesetId)` | block tiles, walkable tiles, grass tile |
| Field metadata | `mod.content.field:get(...)` | ledge rows and restricted tile pairs |
| Topology | current runtime map definition | connections, usable source cells, warps |

A map stores a grid of block IDs. A Gen 1 block contains a `4x4` tile grid and
corresponds to `2x2` movement cells. Collision for a movement cell is determined
by its bottom-left tile. Tile and block IDs are tileset-scoped and are never
treated as global semantic IDs.

## Classification Rules

| Observation | Automatic meaning | Confidence |
| --- | --- | --- |
| Overview `.` | `OPEN_GROUND` | reliable coarse class |
| Overview `~` | `WATER` | reliable coarse class |
| Collision tile equals tileset `grassTile` | `TALL_GRASS` | reliable tileset-scoped class |
| Overview `+` plus topology warp | map transition | reliable topology fact |
| Out-of-bounds edge plus resolved connection | `MAP_CONNECTION` | reliable topology fact |
| Other out-of-bounds edge | `MAP_BOUNDARY` | conservative fallback |
| Stock directed ledge row matches tile pair | `LEDGE` | reliable directed edge evidence |
| Stock restricted tile pair matches | `ELEVATION_RESTRICTION` | reliable edge evidence |
| Land-water neighbors | `WATER_BOUNDARY` and `WATER_ADJACENT` | derived context |
| Grass with non-grass neighbor | `GRASS_EDGE` | derived context |
| Blocked cell with no annotation | `UNKNOWN_BARRIER` | deliberately conservative |

Blocked geometry alone cannot distinguish a tree, fence, wall, building, rock,
or cliff. Those meanings require a tileset-scoped block/tile annotation or a
map-scoped cell/edge annotation. Map annotations override tileset annotations,
which override automatic coarse classification.

## Query Surface

- `describeCell(semantics, x, y)` returns terrain, cover, landing facts, and raw
  map/tileset/block/tile provenance.
- `describeContext(semantics, x, y)` adds grass-edge and water-adjacency context.
- `describeEdge(semantics, x, y, direction)` returns boundary, barrier, topology,
  and declared executable/future traversal modes.
- `scanNeighborhood(...)` provides a bounded square scan with counts and cells.
- `findNearbyFeature(...)` returns deterministic nearest matches by semantic tag.
- `inspect(...)` is an explicit, low-volume human-readable cell/edge diagnostic.
- `metricsSnapshot(...)` exposes query, classification, and cache-hit counters.

Legacy `cellAt`, `edgeAt`, landing, spawn, transition, and line-of-sight methods
remain available for existing spawn and navigation consumers.

## Traversal Boundary

Only stock `WALK` and existing `SWIM` facts can be marked executable. Fence,
cliff, ledge, elevation, and land-water edges may declare future capabilities
such as `SQUEEZE`, `JUMP`, `CLIMB`, `SWIM`, or `FLY`; this is metadata, not an
executor. Unknown barriers fail closed. No code bypasses stock collision.

## Representative Audit

`tests/world_semantics_real_data_spec.lua` loads the installed ROM-derived
Gen1Recomp cache when available and skips cleanly elsewhere. It verifies:

- Route 22 is `40x18` cells, has real tall grass, and yields directed ledges.
- Route 22 `(28,3)` remains an unknown solid barrier while `(28..31,4..5)` is
  the known walkable rival corridor.
- Route 21 `(5,0)` is water.
- Pallet Town `(2,17)` is walkable shore and its north edge can be a connection.
- Rock Tunnel 1F is cave/non-outdoor context.
- Oak's Lab is interior/non-outdoor context.
- Two repeated whole-map context passes exceed a `95%` cell-cache hit rate.

Run the explicit audit summary with:

```powershell
$env:WORLD_SEMANTICS_AUDIT='1'
& 'C:\Program Files\Lua\lua55.exe' tests\world_semantics_real_data_spec.lua
```

The implementation audit observed `40` Route 22 grass cells, `56` directed
ledge edges, and a `1.000` repeat-query cell-cache hit rate. Ten isolated runs,
including Lua startup and generated registry loading, measured `130.37-148.39`
ms (`136.37` ms mean) on the development machine.

## Extension Seams

New reliable engine facts belong in `semantic_source.lua`. New static meanings
belong in `semantic_annotations.lua` and must be scoped by tileset and optionally
map/cell/edge. New actor capability checks belong in `TraversalEvaluator`. New
preferences, needs, habitat scores, and destination choice belong in behavior or
species ecology code. Navigation continues to consume generic `SpatialGoal`
positions; environmental semantics does not own a second planner.