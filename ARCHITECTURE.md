# Wild Ecology Architecture

## 1. Purpose and Ownership

Wild Ecology is a standalone Gen1Recomp mod for persistent wild Pokemon, visible overworld populations, naturalistic behavior, generic entity-to-entity relationships, social learning, and future voluntary joining.

Persistent entities own identity, individual biology and temperament, sparse directed relationships, memory, and population/home data. Runtime avatars are disposable representations of those entities. The player uses the same relationship target representation as every other entity; there are no player-only relationship fields. Reference mods may inform implementation choices but are not dependencies.

Gen1Recomp is an immutable runtime dependency. Wild Ecology uses documented public APIs and narrowly isolated stock-runtime operations through existing world/avatar seams. It does not require a custom engine build.

## 2. Composition and Adapters

[main.lua](main.lua) is the composition and lifecycle root. It loads modules, initializes persistence, owns map/runtime transitions, drives ecology updates, and connects diagnostics. [src/world/runtime_avatar_adapter.lua](src/world/runtime_avatar_adapter.lua) is the lifecycle and movement boundary backed by [src/world/avatar_factory.lua](src/world/avatar_factory.lua) and stock runtime operations. Engine internals and runtime-object mutation stay inside the existing world/avatar seams.

`Save` receives [src/adapters/gen1/persistence_adapter.lua](src/adapters/gen1/persistence_adapter.lua). The backend treats state as opaque data:

```text
load(namespace) -> value, status, optional detail
status          -> ok | not_found | error
save(namespace, state) -> boolean
```

[src/core/save.lua](src/core/save.lua) owns schema versioning, validation, migration, and persistent snapshot filtering. The removed abstract persistence table was documentation scaffolding, not a runtime interface or superclass.

[src/adapters/pokemon_mechanics.lua](src/adapters/pokemon_mechanics.lua) owns generation-neutral mechanics registration and lookup. [src/adapters/gen1/pokemon_mechanics.lua](src/adapters/gen1/pokemon_mechanics.lua) owns the Gen I implementation. Registration and implementation remain separate layers.

[src/world/semantic_source.lua](src/world/semantic_source.lua) and [src/world/engine_topology.lua](src/world/engine_topology.lua) normalize host facts. [src/world/world_semantics.lua](src/world/world_semantics.lua) interprets those facts. New host integrations should extend these established boundaries rather than introduce speculative adapters.

## 3. Persistence and Reconstruction

The current save schema is **8**, and all migrations remain supported. Persistence contains plain durable data, not live execution state.

The following never persist as live execution state:

- `RuntimeState` and runtime NPC handles
- queued commands and active motion
- navigation routes, route history, and movement claims
- rejection and perception caches
- semantic snapshots and caches
- audit buffers
- resolved static species profiles

Avatar destruction or reconstruction clears transient state. The entity then observes current conditions and deliberates afresh.

Durable home areas, drive records, individual circadian variation, location/concealment records, and coarse dormant evidence are separate plain-data records and remain persistent. Dormant last-cell evidence is evidence about a prior location, not a persisted executable route or queued movement command.

## 4. Relationship and Event Ownership

Relationships are sparse and directed. A-to-B and B-to-A are independent canonical records. [src/entities/relationships.lua](src/entities/relationships.lua) allocates a record through `Relationships.getOrCreate` only when meaningful evidence requires one.

Investigation completion uses the completed episode target and that target's canonical relationship, even if the next intent targets another entity. Social alarm may influence fear about a target, but it must not invent direct-threat identity or persistent direct-threat memory.

Future joining must preserve generic relationship ownership and end in the normal owned-Pokemon pipeline. There is no separate ecology-owned Pokemon representation after joining.

## 5. Scheduling, Behavior, and Motion

Perception, Fear integration, high-level deliberation, and current-intent execution are distinct responsibilities. `behaviorDecisionCount` counts completed high-level evaluations, not execution-only ticks.

`INITIAL` entry is one decision, including when it handles an emergency. New severe or emergency evidence may interrupt the current intent. Sustained FLEE does not force high-level deliberation every tick.

Behaviors choose desired states and goals. Generic navigation plans paths. The stock avatar adapter executes collision-authoritative `WALK`. [src/navigation/traversal_capabilities.lua](src/navigation/traversal_capabilities.lua) currently exposes only `WALK` as executable; declarations such as `SWIM`, `FLY`, `CLIMB`, or `JUMP` describe biology or future capability and do not grant an executor. Collision-skipping `scriptMove` is never a fallback.

## 6. Episode Lifetimes

Route, history, and target ownership follows behavior plus target identity, or goal/map identity where applicable. A same-target or same-goal replan may retain useful episode evidence. Retargeting, owner change, map change, or reconstruction clears the applicable stale state.

FLEE keeps its specialized escape policy while sharing bounded search and episode mechanics. Leaving FLEE must not leak its route, escape reference, or history into another intent. Fear and post-FLEE recovery have separate lifetimes and are not erased merely because a route is cleared.

Queued movement requests belong to their current owner. A stock motion already accepted by the engine may finish after behavior ownership changes; the new behavior owns the next step. Movement claims require a matching live request or active motion. Actuator collision-rejection knowledge may survive a behavior transition, but is cleared at the runtime boundary.

Purposeful REST may navigate to a compatible site before resting. REST is not restricted to stationary execution.

## 7. World Semantics

`WorldSemantics` answers objective questions about a map location or boundary. Motivation, actor legality, and route planning have separate owners:

```text
Gen1Recomp public snapshot and registries
  -> SemanticSource (raw provenance)
  -> WorldSemantics (cell, context, edge, transition meaning)
  -> TraversalEvaluator (current actor legality)
  -> NavigationPlanner (route)
  -> behavior / needs / species ecology (desire)
```

Semantic snapshots and their caches are transient.

### Source Inventory

| Fact | Source representation | Semantic use |
| --- | --- | --- |
| Coarse collision | `mod.world:mapOverview().rows` | walkable, water, warp, blocked |
| Map definition | `mod.content.maps:get(mapId)` | dimensions, block IDs, tileset ID |
| Tileset definition | `mod.content.tilesets:get(tilesetId)` | block tiles, walkable tiles, grass tile |
| Field metadata | `mod.content.field:get(...)` | ledge rows and restricted tile pairs |
| Topology | current runtime map definition | connections, usable source cells, warps |

A map is a grid of block IDs. A Gen I block contains a `4x4` tile grid and represents `2x2` movement cells; the bottom-left tile determines collision for a movement cell. Tile and block IDs are tileset-scoped, never global semantic IDs.

### Classification and Annotations

| Observation | Automatic meaning |
| --- | --- |
| Overview `.` | `OPEN_GROUND` |
| Overview `~` | `WATER` |
| Collision tile equals tileset `grassTile` | `TALL_GRASS` |
| Overview `+` plus topology warp | map transition |
| Out-of-bounds edge plus resolved connection | `MAP_CONNECTION` |
| Other out-of-bounds edge | `MAP_BOUNDARY` |
| Stock directed ledge row matches tile pair | `LEDGE` |
| Stock restricted tile pair matches | `ELEVATION_RESTRICTION` |
| Land-water neighbors | `WATER_BOUNDARY`, `WATER_ADJACENT` |
| Grass with non-grass neighbor | `GRASS_EDGE` |
| Blocked cell without annotation | `UNKNOWN_BARRIER` |

Unknown barriers fail closed. Blocked geometry alone cannot establish whether an obstacle is a tree, fence, wall, building, rock, or cliff. Map annotations override tileset annotations, which override automatic coarse classification.

### Query and Extension Surface

- `describeCell` returns terrain, cover, landing facts, and raw provenance.
- `describeContext` adds grass-edge and water-adjacency context.
- `describeEdge` returns boundary, barrier, topology, and traversal declarations.
- `scanNeighborhood` performs a bounded square scan.
- `findNearbyFeature` returns deterministic nearest matches by semantic tag.
- `inspect` emits an explicit, low-volume diagnostic.
- `metricsSnapshot` exposes query, classification, and cache counters.
- Legacy cell, edge, landing, spawn, transition, and line-of-sight APIs remain available to current consumers.

New reliable engine facts belong in `semantic_source.lua`. New static meanings belong in `semantic_annotations.lua`, scoped by tileset and optionally map/cell/edge. Actor capability checks belong in `TraversalEvaluator`. Preferences, needs, habitat scores, and destination choice belong in behavior or species ecology. Navigation continues to consume generic `SpatialGoal` positions. Only `WALK` currently has an executor.

## 8. Needs, Feeding, Rest, and Home

Drives are elapsed-time-normalized deficits with separate activation and release thresholds. `NeedStrategy` requires compatible, reachable semantic opportunities. Utility decides whether to act; intent completion owns satisfaction.

`WATER_ADJACENT` supports drinking. `TALL_GRASS_FORAGE` is the only current food opportunity. It represents bounded, abstract compatible forage such as seeds, insects, or vegetation associated with proven tall grass, and uses transient local depletion. It does not mean every species eats grass. Unsupported species retain hunger rather than consume unsuitable terrain.

REST motivation and rest-site choice are separate. Only proven, compatible `TALL_GRASS` currently supports concealed rest. Emergence requires a fresh legal materialization cell.

`HomeArea` is a durable local area, not `spawnX`/`spawnY` or a requirement to occupy its exact anchor. `RETURN_HOME` uses generic utility and navigation with inner/outer area hysteresis. Schedules, cross-map homing, and territory are not implemented.

## 9. Clock and Dormancy

`EcologyClockAdapter` normalizes `REAL_TIME`, `SIMULATION`, and `FIXED` sources. Backward time never reverses ecology. Changing incompatible sources rebases elapsed time. Simulation mode freezes while the mod is closed; returning in real-time mode permits bounded coarse catch-up.

Circadian curves bias utility and never issue commands. Before teardown, the lifecycle captures dormant cohorts from actors actually materialized at unload. Catch-up runs once before rematerialization and uses bounded analytical/coarse integration, never missed-tick replay or offscreen pathfinding.

Actor-scoped proven drive opportunities and sparse social evidence constrain catch-up. Dormancy does not fabricate attacks, conflict, resource discoveries, or live events.

## 10. Species Authoring

Species ecology is static biological data. It does not own temperament, learned moves, relationships, current drives, runtime movement, or engine objects.

### Resolution

`SpeciesEcology.resolve(speciesId)` returns a fresh copy composed in this order:

1. Conservative fallback
2. Selected ecological archetype
3. Species override

Unknown species use the conservative `solitary` fallback. `SpeciesEcology.getResolved(speciesId)` is the shared cached read path for consumers that do not mutate the profile.

[src/species/archetypes.lua](src/species/archetypes.lua) supplies Fear and alarm defaults. [src/species/ecology_archetypes.lua](src/species/ecology_archetypes.lua) supplies ecological composition defaults. Both are live and serve different layers. Individual temperament and mechanics remain separate from species ecology.

Resolved profiles never persist. Durable entities retain only genuine individual state such as family, circadian variation, mechanics, temperament, relationships, and memory.

### Fields

| Field | Type/range | Default | Current owner/consumer | Classification |
| --- | --- | --- | --- | --- |
| `archetype` | known string ID | `solitary` | resolver, Fear archetype lookup | biological baseline |
| `activityProfile` | known circadian ID | `FLEXIBLE` | `CircadianSystem` | biological baseline |
| `social.modifier` | number, 0-2 | `0.25` | social exposure, flock search | species social baseline |
| `social.familyModifier` | number, 0-2 | `0.75` | social exposure | species social baseline |
| `social.desiredGroupSize` | number, 1-12 | `1` | flock search | species social baseline |
| `physiology.thirstRate` | number, 0.5-2 | `1` | live and dormant physiology | biological rate |
| `physiology.hungerRate` | number, 0.5-2 | `1` | live and dormant physiology | biological rate |
| `physiology.fatigueRate` | number, 0.5-2 | `1` | live and dormant physiology | biological rate |
| `physiology.restRecovery` | number, 0.5-2 | `1` | live and dormant physiology | biological rate |
| `movement.wanderScale` | number, 0.5-1.5 | `1` | ambient wander after TARGET selection | physical pacing |
| `home.radius` | number, 1-5 | `2` | home-area establishment | biological area scale |
| `home.attachment` | number, 0.5-1.5 | `1` | RETURN_HOME utility context | biological attachment tendency |
| `home.roamingTolerance` | number, 1-6 | `2` | RETURN_HOME activation boundary | biological roaming tendency |
| `habitat` | ranked known string list | `GENERAL` | inspector; future habitat choice | declarative metadata |
| `restSites` | ranked known string list | `SHELTER`, `COVER` | rest-site resolver when proven semantics exist | biological preference |
| `concealmentSites` | array of known IDs | empty | rest-site resolver and concealment lifecycle | biological compatibility |
| `biologicalCapabilities` | known mode to boolean | `WALK=true` | `TraversalCapabilities` | biological declaration only |
| `feeding.acceptedOpportunityTypes` | array of known IDs | empty | food opportunity resolver | biological compatibility |
| `join` | threshold numbers, 0-100 | absent | retained declarative thresholds; no wired joining implementation | future rule |

Home parameters affect persistent area size and generic return pressure but never issue behavior. A species social baseline never creates relationships. `TALL_GRASS_FORAGE` is currently accepted by Pidgey, Rattata, and Caterpie; profiles without a proven compatible resource retain hunger. Join profile data, validation, and telemetry thresholds remain live declarations, but joining is not wired into ownership or battle integration.

### Adding a Species

Choose the closest archetype and add only meaningful biological differences to `src/species/profiles.lua`:

```lua
ODDISH = {
  archetype = "sheltered_grazer",
  activityProfile = "NOCTURNAL",
  habitat = { "GROUND_COVER", "WOODLAND_EDGE" }
}
```

Do not repeat archetype values. Add an archetype only when several species need a coherent combination that existing archetypes cannot express. Archetypes are flat composition, not inheritance. Personality belongs to individual generation and temperament. Raw stats and move IDs enter through `PokemonMechanicsAdapter` and `MoveSemantics`.

### Validation and Inspection

Definitions are validated when `SpeciesEcology` loads. Validation rejects unknown archetypes, source or nested fields, activity profiles, habitat/rest enums, capability names, malformed types, and out-of-range values.

- `SpeciesEcology.validateDefinitions(archetypes, profiles)` validates fixture tables.
- `SpeciesEcology.inspect(speciesId)` returns a compact resolved baseline.
- `SpeciesEcology.resolve(speciesId)` returns a fresh copy.
- `SpeciesEcology.getResolved(speciesId)` returns the shared cached profile.

Focused validation uses `tests/species_ecology_profiles_spec.lua`, `tests/mechanics_ecology_spec.lua`, `tests/circadian_spec.lua`, and `tests/dormant_cohort_spec.lua`.

## 11. Diagnostics

The relationship audit is the directed semantic journal. It records meaningful relationship creation and changes. The light agent audit records unordered physical encounters while retaining separate A-to-B and B-to-A summaries, encounter completion, and anomalies.

Full forensic mutation/context/history output requires both `AGENT AUDIT` and `BEHAVIOR TRACE`. Audit output uses record-aware 196 KiB numbered rollover, buffered writes, and runtime-only recorder state. Logging observes the simulation; it must never become a source of simulation mutations. User-facing enable/disable instructions are maintained in [README.md](README.md#relationship-audit-log).

## 12. Validation and Limits

Deterministic tests run in fresh Lua processes so module state cannot leak between specs. The standard entry point is the sorted `tests/*_spec.lua` suite using Lua 5.5.

`tests/world_semantics_real_data_spec.lua` reads ROM-derived fixtures from `GEN1RECOMP_RED_CACHE`, or from the normal generated cache under `%APPDATA%` when available. It skips cleanly when generated maps, tilesets, or field data are unavailable. A skipped test is not a real-map pass.

Headless tests, fake persistence backends, and fake runtime-avatar adapters establish deterministic contracts at their boundaries. They do not establish full live-engine behavior or universal portability. Implemented foundations are documented here; incomplete and future work remains in [WILD_ECOLOGY_ROADMAP.md](WILD_ECOLOGY_ROADMAP.md).
