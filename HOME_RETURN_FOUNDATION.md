# Local Home-Return Foundation

## Scope

This foundation gives each eligible persistent wild Pokemon a stable local
home area and a context-sensitive `RETURN_HOME` behavior. An actor may leave
home for ordinary ecology. Distance, circadian rest bias, fatigue, species
attachment, and individual temperament can later make return worthwhile.
Generic utility chooses the behavior, generic navigation executes it, and
entering any acceptable part of the area satisfies it.

This is not a schedule, bedtime, territory, nest, den, migration system, or
cross-map homing implementation.

## Previous Home-Related State

Before this feature, `entity.home` already belonged to the persistent entity and
contained:

- `mapId`: population/materialization map;
- `zoneId`: population placement cohort label;
- `spawnX` and `spawnY`: deterministic materialization coordinates;
- transient/debug spawn viability metadata.

`PopulationManager.assignSpawnCells` selected legal, non-overlapping placement
cells from current `WorldSemantics` and preserved existing values. Avatar
creation used those coordinates. No behavior consumed `entity.home`, no area
membership query existed, and no `RETURN_HOME` utility/state existed.

The existing table had the correct persistent owner, so this feature extends it
rather than creating a second top-level home representation. `spawnX/Y` remains
materialization placement; it is not the ecological meaning of home.

## Durable Representation

Schema v8 adds `entity.home.area`:

```lua
{
  mapId = "ROUTE_1",
  anchorCell = { cellX = 8, cellY = 12 },
  radius = 2,
  establishedTick = 120,
  provenance = "POPULATION_PLACEMENT"
}
```

The anchor is a compact implementation aid. Home means every legal local cell
within the bounded Chebyshev radius, not exact anchor occupancy. Radius is
bounded from one through five cells.

The record contains only plain serializable data. It never contains an avatar,
route, selected destination, utility score, semantic object, host handle, or
navigation episode.

## Assignment

`PopulationManager.assignSpawnCells` establishes an area only when all of the
following are true:

- the persistent entity does not already have an area;
- deterministic population placement has supplied `spawnX/Y`;
- current semantics match the entity map;
- the anchor is in bounds;
- the anchor has no transition/warp semantic;
- WALK is currently an executable legal landing there.

The existing legal placement seeds the area but is not itself the area.
SpeciesEcology supplies the bounded radius. Provenance is
`POPULATION_PLACEMENT`, and `establishedTick` is the current simulation tick.

Repeated assignment, semantics refresh, map revisit, save/load, concealment,
and rematerialization return the existing area without regenerating it. If a v7
entity lacks sufficient live semantic evidence, migration leaves the area unset.
The next valid live population assignment establishes it deterministically.

No random home is invented during load.

## Species and Individual Influence

Validated `SpeciesEcology.home` contains:

- `radius`: typical local area size, 1-5;
- `attachment`: return-pressure multiplier, 0.5-1.5;
- `roamingTolerance`: distance beyond the area tolerated before return pressure
  starts, 1-6.

These parameters are inherited through fallback, archetype, and species profile
composition. They cannot directly issue behavior. Static values are stripped
from persistent snapshots.

Existing `rawStats.independence` and temperament `boldness` modestly adjust the
resolved attachment multiplier. No new personality subsystem or stat-derived
psychology was introduced. Individuals of one species can therefore differ
without species-specific controller branches.

## Membership and Hysteresis

`HomeArea.isInside` is a constant-time Chebyshev-distance query:

```text
distance(position, anchor) <= radius
```

Map identity must match when supplied. A concealed actor uses the durable
`locationState.anchorCell`, so hidden membership requires no avatar or
rematerialization.

Two boundaries prevent chatter:

- satisfaction boundary: inside `radius`;
- activation boundary: beyond `radius + roamingTolerance`.

An inactive actor just outside the home area receives no return score. Once
`RETURN_HOME` is active, the existing purposeful intent commitment keeps it
active until the actor enters the satisfaction area or a superior purposeful or
emergency behavior interrupts it. There is no home-specific timer.

## Utility

`HomeReturn.evaluate` produces normalized context facts and a score only when a
valid same-map area and current position exist. Return pressure combines:

- distance beyond the activation boundary;
- normalized circadian rest bias;
- FATIGUE;
- resolved species attachment;
- modest independence/boldness variation;
- fatigue-limited travel capacity.

It never compares against a clock hour. Diurnal/nocturnal differences emerge
from the existing `CircadianSystem` output.

Extreme FATIGUE sharply lowers travel capacity while ordinary REST utility rises,
so an exhausted actor can rest locally. Strong THIRST/HUNGER opportunities keep
their ordinary `SATISFY_NEED` scores and can beat moderate return pressure.
Severe threat still forces the existing FLEE path. No priority table,
`HOME_FLEE`, or home safety exception exists.

Ambient wandering remains unconstrained. It may carry an actor outside home;
return pressure grows gradually afterward rather than hard-blocking movement.
Purposeful drinking, foraging, investigation, social travel, and FLEE are not
penalized merely for crossing the area boundary.

## Destination and Navigation

After `RETURN_HOME` wins, `HomeArea.selectDestination` scans only the bounded
home square, at most 11 by 11 cells. Candidates must be:

- within the area radius;
- inside the authored map;
- non-transition cells;
- valid WALK landings.

The nearest acceptable cell to the actor wins, with stable Y/X tie-breaking.
The destination is usually an area boundary cell, not the anchor.

The controller creates `SpatialGoal.position(..., source="HOME_AREA")` and calls
`NavigationExecution.navigate` with owner `RETURN_HOME`. NavigationPlanner,
NavigationEpisode, occupancy, collision, and movement execution remain generic.
No HomePathfinder or special traversal was added.

When membership becomes true, `IntentEpisode` marks `RETURN_HOME` satisfied.
The controller clears destination/navigation state and returns to `SETTLED`.
Normal utility may subsequently select REST, concealed REST, foraging, drinking,
social behavior, or ambient activity. Returning home does not imply sleep.

## REST and Concealment

HOME and REST remain independent:

- severe FATIGUE can select local REST instead of travel;
- moderate FATIGUE and low activity can raise both scores normally;
- after return, RestSiteResolver independently chooses visible or concealed
  rest;
- REST away from home remains valid;
- home-site quality does not alter recovery rate.

Concealment does not erase or alter home. A concealed actor inside the area is
already home. Existing disturbance can still wake, cue, emerge, or trigger FLEE
there; home provides no threat suppression.

## Persistence and Materialization

Persisted:

- map, anchor, radius, establishment tick, and provenance;
- existing materialization coordinates;
- existing drives, identity, relationships, and concealed location.

Not persisted:

- `RETURN_HOME` state or score;
- selected destination or candidate list;
- SpatialGoal;
- NavigationExecution/NavigationEpisode state;
- avatar/runtime identity;
- current semantic object.

Schema v8 migration validates any existing area shape and preserves all v7
concealment, drives, relationships, personality, and clock data. It leaves
unproven old homes unset. Current-schema loads normalize radius/provenance and
discard malformed areas.

Before ordinary avatar destruction on map unload, the lifecycle reads the
avatar's normalized local cell and updates existing `spawnX/Y`. This preserves
last local materialization locality without changing `home.area`, so unloading
outside home does not fabricate a completed return trip. Concealed actors are
not active avatars and retain their authoritative `locationState` instead.

Visible-subset selection remains independent. Home residence does not guarantee
materialization, and overlapping home areas do not allocate relationships.
Fresh rematerialization receives a new runtime ID while the persistent entity
and exact home-area record remain unchanged.

## Dormancy

Dormant actors retain home data, but dormant catch-up does not simulate routes,
choose destinations, or fabricate arrival. Drives and circadian state continue
through the existing analytical cohort simulator. A visible actor's last local
materialization coordinate is retained at unload; a concealed actor retains its
concealment anchor.

No cross-map transition is executed or inferred. An area is local to one authored
map.

## Diagnostics and Performance

`EcologyInspector.actor` adds one compact HOME line containing establishment,
map, anchor, radius, membership, distance, score, active-return state,
destination, and provenance. It emits no continuous log.

Per-deliberation membership and distance are constant time. Destination search
runs only after `RETURN_HOME` is selected or its transient destination is lost,
and checks at most 121 cells. It never scans the whole map. Route planning is
owned by the existing generic navigation system.

## Current Limits

- Home remains stable; there is no relocation or abandonment.
- No territory ownership, exclusion, marking, or defense.
- No shared family/group home records or relationship creation from overlap.
- No dens, nests, roosts, favorite beds, resource ownership, or home quality.
- No schedules, bedtime, or sunrise/sunset behavior commands. Composed
  long-horizon behavior is proven separately without adding those concepts.
- No migration, cross-map homing, transition execution, or off-playable travel.
- No home-biased FLEE or claim that home is safe.
- WALK is the only executable assignment/destination traversal mode.
- No detailed offscreen RETURN_HOME navigation.

Long-horizon composition and activity continuity are now audited in
`COMPOSED_DAILY_RHYTHM_AUDIT.md`. The next evidence-driven Phase 8 extension is
broader proven resource/rest semantics for currently unsupported profiles.
