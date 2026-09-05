# Portability Adapter Re-Audit

## Scope and decision

This is an audit-only reassessment after completion of the two P0 boundaries.
It does not implement P1 adapters, refactor production code, add gameplay
features, expand SpeciesEcology, or implement battle, capture, trading,
ownership transfer, concealment, or cross-map execution.

**Decision: resume feature development. No additional portability refactor is
required first.** Current host dependencies are concentrated in replaceable
source, runtime, presentation, bootstrap, and diagnostic implementations.

An adapter is justified only when replacing an external system would otherwise
require changes to portable ecology logic and the interface owns one coherent
external responsibility. The default is not to create one.

## Method

Repository source and tests control this audit. The required quedonde workflow
was run after reading its README. Migration and indexing succeeded, but a clean
rebuild indexed only 28 tracked files and could not see the current untracked
Lua architecture files. Direct symbol searches and source reads therefore
control the conclusions.

Every meaningful dependency is assigned exactly one classification:

1. FIRST-CLASS ADAPTER REQUIRED
2. FORMALIZE EXISTING ADAPTER
3. MERGE INTO EXISTING ADAPTER
4. STABLE WILD ECOLOGY ABSTRACTION
5. INTERNAL IMPLEMENTATION DETAIL
6. DEFER UNTIL FEATURE EXISTS
7. DO NOT ADAPTERIZE

## COMPLETED

| Boundary | Contract and ownership | Classification |
|---|---|---|
| Runtime avatars | `RuntimeAvatarAdapter` owns materialize, destroy, resolve, position reads, and movement requests; `AvatarFactory` contains Gen1Recomp NPC and Collision details | 1. FIRST-CLASS ADAPTER REQUIRED, complete |
| Persistence | `Save` owns schema/migrations/safety; `Gen1PersistenceAdapter` owns opaque host read/write | 1. FIRST-CLASS ADAPTER REQUIRED, complete |
| Pokemon mechanics | Portable snapshots hide DVs, statExp, PP Ups, shared Special, and native Pokemon records | 1. FIRST-CLASS ADAPTER REQUIRED, complete |
| Ecology clock | Fixed, simulation, and real-time inputs produce one normalized sample | 2. FORMALIZE EXISTING ADAPTER, complete |
| World meaning | `WorldSemantics` and `WorldTopology` expose normalized cells, edges, transitions, and topology | 4. STABLE WILD ECOLOGY ABSTRACTION |

The production leak scan found raw NPC motion fields only in
`runtime_avatar_adapter.lua` and `avatar_factory.lua`; Gen I mechanics fields
only in `adapters/gen1/pokemon_mechanics.lua`; and persistent ecology-state
storage calls only in `adapters/gen1/persistence_adapter.lua`.

## CURRENTLY JUSTIFIED

No new adapter is currently justified. These existing modules are valid host
edges:

- `semantic_source.lua` translates `mapOverview` and map, tileset, and field
  registries into a plain semantic snapshot.
- `engine_topology.lua` translates the runtime map graph into plain connections,
  usable source cells, warps, dimensions, and environment class.
- `environment.lua` performs the sole encounter-registry lookup and returns
  `{ species, level }` to generation.
- `species_sprites.lua` owns host sprite discovery and registration.
- `main.lua` composes implementations and owns hooks, UI, lifecycle, active
  world access, and diagnostic output.

## DEFERRED

| Responsibility | Classification | Revisit when |
|---|---|---|
| Battle start/result events | 6. DEFER UNTIL FEATURE EXISTS | A real battle bridge exists |
| Capture and voluntary ownership | 6. DEFER UNTIL FEATURE EXISTS | Joining enters the normal ownership pipeline |
| Party, box, evolution, trade, transfer | 6. DEFER UNTIL FEATURE EXISTS | A real owned-record association is required |
| Habitat/encounter source | 6. DEFER UNTIL FEATURE EXISTS | Multiple ecology systems need one normalized contract |
| Cross-map execution | 6. DEFER UNTIL FEATURE EXISTS | Descriptive transitions become executable |
| Presentation backend | 6. DEFER UNTIL FEATURE EXISTS | A second backend or repeated consumer exists |

## NOT RECOMMENDED

| Proposal | Classification | Reason |
|---|---|---|
| Generic `GameContentAdapter` | 7. DO NOT ADAPTERIZE | It would combine unrelated maps, encounters, Pokemon, moves, sprites, and UI into a service locator |
| `WorldTopologySource` wrapper | 7. DO NOT ADAPTERIZE | `EngineTopology` is already the replaceable source |
| Adapter around `WorldTopology` | 7. DO NOT ADAPTERIZE | It is portable domain logic over normalized semantics |
| Navigation/traversal adapter | 7. DO NOT ADAPTERIZE | Planners already consume semantics and capabilities only |
| UI/settings adapter | 7. DO NOT ADAPTERIZE | UI is host integration, not a domain dependency |
| Debug/logging adapter | 7. DO NOT ADAPTERIZE | Audit writers are injectable; main's byte writes are diagnostic I/O |
| Relationship/fear/drive/behavior adapters | 7. DO NOT ADAPTERIZE | These modules define Wild Ecology meaning |

## Dependency map

| External dependency | Current owner | Boundary output | Classification |
|---|---|---|---|
| `mod.world`, `engine_internals`, Collision, NPC motion fields | runtime adapter and avatar factory | Avatar lifecycle, position, movement result | 1, complete |
| `mod.storage:read/write` | Gen1 persistence adapter | Opaque state and explicit load status | 1, complete |
| Gen I Pokemon records | Gen1 mechanics adapter | Normalized mechanics snapshot | 1, complete |
| `os.time`, `os.date` | ecology clock adapter | Ecology clock sample | 2, complete |
| `mapOverview`, maps, tilesets, fields | semantic source | Semantic snapshot | 5. INTERNAL IMPLEMENTATION DETAIL |
| runtime map, `map.def`, connections, warps | engine topology | Topology descriptor | 5. INTERNAL IMPLEMENTATION DETAIL |
| normalized cells, edges, transitions | world semantics/topology | Ecology world meaning | 4. STABLE WILD ECOLOGY ABSTRACTION |
| encounters/constants registries | environment | Optional species/level input | 5. INTERNAL IMPLEMENTATION DETAIL |
| Pokemon/sprite registries and assets | species sprites | Runtime sprite ID | 5. INTERNAL IMPLEMENTATION DETAIL |
| hooks, screens, options, active world, diagnostic `writeBytes` | main | Composition and diagnostics | 7. DO NOT ADAPTERIZE |
| `mod.world:current()` player position | playable component | `{ cellX, cellY }` | 5. INTERNAL IMPLEMENTATION DETAIL |
| map raster convenience reads | walkable cells | Walkable cell list | 5. INTERNAL IMPLEMENTATION DETAIL |
| `os.time()` memory fallback | entity memory | Event timestamp | 5. INTERNAL IMPLEMENTATION DETAIL |
| battle/capture/transfer APIs | placeholders only | No live contract | 6. DEFER UNTIL FEATURE EXISTS |

## World topology

**Recommendation: LEAVE AS-IS.**

`EngineTopology` reads Gen1Recomp's stack, map definitions, map module, and data
registries, then emits plain topology. `WorldSemantics` combines that topology
with a semantic snapshot. `WorldTopology`, `NavigationPlanner`,
`TraversalEvaluator`, spawn analysis, and behavior consume the normalized model,
not `map.def` or `game.data`.

A new engine replaces EngineTopology and the semantic source. Planner,
traversal, behavior, and relationship code do not change. Another wrapper would
add indirection without moving a dependency or stabilizing a new contract.

## Content, environment, and presentation

Raw registry access is concentrated in SemanticSource, Environment, and
SpeciesSprites; it does not leak into portable behavior, navigation,
relationships, circadian simulation, dormant simulation, or phenotype logic.
These responsibilities should remain separate rather than become a generic
content adapter.

Environment is not yet a coherent adapter: `getCellTags` is a stub,
`evaluateTraversal` has no production caller, and `getWildEncounterTable` is one
host reader. It returns a normalized result and generation already falls back to
configured pools headlessly. Revisit it when environmental semantics define a
real multi-consumer contract.

SpeciesSprites is presentation implementation. Sprite IDs affect disposable
avatars, not persistent authority or ecology decisions. A presentation adapter
is deferred.

## Composition root and diagnostics

`main.lua` is large and host-heavy because it is the composition/lifecycle root.
It loads implementations, installs hooks and screens, samples the active world,
and connects diagnostic writers. Another engine rewrites this bootstrap while
retaining the portable modules it composes. Splitting it may improve future
maintainability, but that is not prerequisite portability work.

Main's `mod.storage:writeBytes` calls write diagnostic artifacts, not persistent
ecology state, and do not violate PersistenceAdapter ownership. Relationship and
agent audit policy is testable through injected writer functions.

## Boundary verification

- `src/core/save.lua` has no host-storage knowledge. Save owns schema,
  migrations, snapshots, validation, and overwrite safety.
- Raw NPC targets, movement progress, handles, and coordinates do not appear in
  portable ecology modules.
- DVs, statExp, PP Ups, and unified Special assumptions remain under the Gen I
  mechanics implementation.
- NavigationPlanner and TraversalEvaluator consume normalized semantics.
- Relationships, fear, threat assessment, drives, social behavior, controller,
  intent episodes, circadian systems, dormant cohorts, SpeciesEcology, and
  EcologicalPhenotype remain adapter-free domain logic.

The `os.time()` fallback in Memory is a determinism cleanup candidate if events
without ticks must support replay. It does not justify another host adapter.

## Headless readiness

Portable ecology is headless-ready at the domain level:

- fixed/simulation clock input avoids host time;
- `WorldSemantics.fromSnapshot` or `fromOverview` avoids runtime map APIs;
- fake runtime and persistence adapters replace actors and storage;
- normalized mechanics snapshots replace Gen I records;
- configured species pools replace encounter registries.

A headless reproduction of main, sprite registration, debug screens, and live
map probing is neither required nor desirable.

## Port scenarios

### Gen II runtime today

Expected replacement or host-specific work:

- `main.lua` for bootstrap, hooks, UI, active world, and diagnostics;
- `runtime_avatar_adapter.lua` and `avatar_factory.lua` for actors/movement;
- a Gen II persistence implementation replacing the Gen1 implementation;
- a Gen II mechanics implementation replacing the Gen1 implementation;
- `engine_topology.lua` and `semantic_source.lua` for maps;
- `environment.lua` if host encounters remain a generation source;
- `species_sprites.lua` for presentation;
- playable-component/walkable-cell host readers only if no equivalent normalized
  world facade exists.

Expected unchanged portable systems:

- Save schema/migrations and population records;
- entities, relationships, fear, drives, social learning, utility, controller,
  episodes, goals, and target selection;
- WorldSemantics and WorldTopology meaning/query operations;
- NavigationPlanner, TraversalEvaluator, and bounded search;
- perception event semantics;
- circadian and dormant simulation;
- SpeciesEcology and EcologicalPhenotype.

### Alternate ECS / JSON-map engine

An ECS backend maps persistent ecology identities to disposable ECS handles. A
JSON loader produces semantic snapshots and normalized topology. A file or
database backend implements opaque persistence. Bootstrap and presentation are
rewritten. The same portable systems remain unchanged because they do not depend
on Gen1Recomp NPC tables, Lua map definitions, registries, or storage signatures.

## Deferred ownership and transfer constraints

Battle, capture, voluntary joining, storage, evolution, trade, and transfer must
wait for real host operations. They must preserve one normal owned-Pokemon
pipeline and keep Wild Ecology state as a sidecar.

Future identity invariant:

- `ecologyId` is opaque and immutable.
- It encodes no species, level, stats, moves, owner, party/box position, or
  native runtime/storage identifier.
- It follows the same individual through capture, voluntary joining, party and
  box storage, evolution, trade, transfer, map transitions, avatar destruction,
  and rematerialization.
- Runtime pointers and generated avatar IDs never become persistent identity.
- Relationships retain generic entity identity; the player gets no special
  relationship representation.

Battle/event observation and ownership mutation are distinct future external
responsibilities and need not become one broad adapter.

## Priority recommendation

**Choose option A: no further portability refactor before feature work.**

1. Resume roadmap feature development.
2. Keep topology as-is.
3. Do not create generic content, topology, presentation, UI, logging, battle,
   capture, or ownership adapters preemptively.
4. Re-audit only when a concrete feature creates a second implementation or raw
   host data begins crossing into portable ecology logic.

## Regression invariants

- Persistent identity survives avatar destruction and rematerialization.
- Runtime objects and in-progress movement are never serialized.
- Runtime lifecycle and movement flow through RuntimeAvatarAdapter.
- Stock collision remains authoritative for executable WALK movement.
- Save remains host-blind; PersistenceAdapter treats state as opaque.
- WorldSemantics remains portable meaning; source modules may know the host.
- Generation-specific Pokemon records remain inside mechanics implementations.
- Relationships remain sparse, directed, generic, and free of player-only data.
- Future ownership work preserves one ownership pipeline and immutable ecology
  identity.

## Conclusion

Both P0 boundaries are complete, and the other high-value normalization seams
already exist. Remaining host knowledge is concentrated in implementation and
composition files. Replacing the host changes those files, not the portable
ecology model.

The architecture is portable enough to resume feature development. Further
adapter work should be driven by a concrete feature or second backend, not by a
standalone P1 adapter program.
