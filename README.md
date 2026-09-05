# Wild Ecology

Standalone Gen1Recomp mod scaffold focused on persistent wild Pokemon simulation.

## Status

This repository has completed the core foundations through **Phase 7
(environmental understanding)**, substantial **Phase 8 foundations**, and the
portable mechanics/species-profile foundation for **Phase 9**:

- A persistent Route 1 population with stable individual IDs
- Minimal save payload via storage adapter
- Avatar spawn seam isolated behind `AvatarFactory` and wired to `mod.world:spawnNpc/removeNpc`
- Route-gated test bootstrap in `main.lua`
- `PHASE0 LOG` mod option toggle for rendering a reusable in-game development log overlay
- `PHASE0 BEHAVIOR` option for forcing `NORMAL`, `FORCE IDLE`, or `FORCE FLEE` during in-game verification
- `PHASE2 SOCIAL FEAR` option for applying trusted-associate fear propagation to the player relationship during in-game verification
- Category toggles and `LOG VIEW` options for filtering lifecycle, behavior, and relationship events during development
- Deterministic visible-subset selection with persistent, non-overlapping spawn cells
- Generic runtime perception events for visible Pokémon and the player
- Stock-runtime collision-aware WALK movement through the isolated `engine_internals` adapter
- Structured, cached cell/context/edge semantics derived from the public world
	snapshot and map, tileset, and field registries
- Conservative terrain and boundary queries for grass, water, transitions,
	ledges, elevation restrictions, and authored map/tileset features
- Generic environmental feature discovery feeding the existing `SpatialGoal`
	and navigation pipeline
- Persistent, normalized biological drives with elapsed-tick updates, separate
	activation/release thresholds, partial satisfaction, save migration, and
	compact diagnostics
- A generic `SATISFY_NEED` intent that lets THIRST find reachable
	`WATER_ADJACENT` terrain, travel there through ordinary WALK navigation,
	drink, and return to `SETTLED`
- Persistent HUNGER using the same intent and navigation path, with validated
	species feeding compatibility, abstract `TALL_GRASS_FORAGE`, bounded
	stationary feeding, transient local depletion, and return to `SETTLED`
- A stable Ecology Clock with real-time, configurable simulation-time, and
	fixed-debug sources, plus explicit backward/forward discontinuity handling
- Smooth persistent circadian activity profiles with modest individual phase
	and amplitude variation feeding utility rather than commanding behavior
- Persistent FATIGUE and purposeful REST with bounded site choice, ordinary
	WALK travel, visible fallback, optional species-compatible tall-grass
	concealment, generic disturbance response, and legal fresh rematerialization
- Stable persistent local home areas with species/individual roaming tendency,
	circadian-sensitive `RETURN_HOME` utility, nearest-area generic navigation,
	inner/outer hysteresis, and ordinary equilibrium after arrival
- Deterministic long-horizon composition proving repeated drinking, foraging,
	REST/concealment, roaming, and home return around substantial `SETTLED`
	equilibrium without a schedule, agenda, or behavior queue
- Bounded dormant-cohort catch-up for actors actually materialized at unload,
	including coarse drives, actor-scoped drive opportunity evidence, and sparse directed social
	exposure without replaying missed ticks or fabricating live events
- A registered `PokemonMechanicsAdapter` boundary that converts canonical Gen I
	Pokemon records into generation-neutral physical mechanics snapshots
- Generation-neutral move semantics that expose ecological options without
	creating motivation, bypassing terrain semantics, or claiming execution
- Bounded ecological phenotypes for mobility, endurance, robustness, physical
	power, and recovery, with no personality output
- Validated fallback/archetype/species ecology layering for eleven representative
	species across eight ecological archetypes, used consistently by live and
	dormant physiology, circadian activity, social baselines, and ambient wander
	scale
- Headless tests for persistence, relationships, population identity, temperament, avatar seam behavior, route exit/re-entry lifecycle, explicit Phase 1 identity reconstruction, and Phase 2 social fear runtime behavior updates

See [WORLD_SEMANTICS_AUDIT.md](WORLD_SEMANTICS_AUDIT.md) for the Phase 7
source inventory, ownership rules, inference limits, and real-map audit.
See [NEEDS_AND_DRIVES_AUDIT.md](NEEDS_AND_DRIVES_AUDIT.md) for drive ownership,
the THIRST proof, persistence behavior, and current Phase 8 limits.
See [HUNGER_FORAGING_FOUNDATION.md](HUNGER_FORAGING_FOUNDATION.md) for feeding
compatibility, opportunity semantics, depletion, dormancy, and current limits.
See [REST_SITE_CONCEALMENT_FOUNDATION.md](REST_SITE_CONCEALMENT_FOUNDATION.md)
for REST ownership, site scoring, concealed presence, disturbance/cue semantics,
emergence, persistence, and current spatial limitations.
See [HOME_RETURN_FOUNDATION.md](HOME_RETURN_FOUNDATION.md) for local home-area
assignment, schema-v8 persistence, utility/hysteresis, generic navigation,
materialization locality, dormancy, and deferred cross-map/territory scope.
See [COMPOSED_DAILY_RHYTHM_AUDIT.md](COMPOSED_DAILY_RHYTHM_AUDIT.md) for the
long-horizon harness, measured behavior occupancy, representative species and
interruptions, production corrections, and Phase 8 exit-condition assessment.
See [ECOLOGY_CLOCK_AND_DORMANCY_AUDIT.md](ECOLOGY_CLOCK_AND_DORMANCY_AUDIT.md)
for clock-source evidence, circadian/REST ownership, dormant simulation rules,
measured performance, persistence boundaries, and deferred scope.
See [SPECIES_ECOLOGY_AUDIT.md](SPECIES_ECOLOGY_AUDIT.md) for official mechanics
evidence, adapter contracts, move/phenotype/profile ownership, proof coverage,
and intentionally deferred execution and content scope.
See [SPECIES_ECOLOGY_PROFILES.md](SPECIES_ECOLOGY_PROFILES.md) for profile
precedence, the consumed-field inventory, validation rules, and the data-only
workflow for adding another species.

## Relationship Audit Log

The compact relationship audit is off by default. Open the in-game Start menu,
select `WILD ECOLOGY LOGS`, and set `REL AUDIT` to `ON`. The change applies
immediately and is retained in the mod save settings. Turning it off flushes
pending records and stops collection without requiring a restart.

Audit files are written under the LOVE save directory, beginning with
`relationship_audit.bin`. Each file is limited to 196 KiB; overflow continues
in `relationship_audit_2.bin`, `relationship_audit_3.bin`, and later files.
This file is the directed semantic journal: it records relationship creation,
meaningful threshold crossings, and atomic direct-threat or hostility changes.
Routine fractional growth does not create journal records.

For root-cause capture, enable `AGENT AUDIT` in the same menu. This separate,
default-off flight recorder writes `agent_audit.bin`, then
`agent_audit_2.bin`, `agent_audit_3.bin`, and later continuation files. It
normally records one start and one end for each unordered physical encounter,
plus investigation completion and rare relationship anomalies. Each encounter
contains separate A-to-B and B-to-A directed relationship summaries. Routine
proximity produces neither periodic samples nor full-state mutation records.
To capture expensive mutation/PRE/EVENT/POST context and periodic samples,
explicitly enable both `AGENT AUDIT` and `BEHAVIOR TRACE`. Turning agent audit
off flushes the active file and releases all transient recorder state.

## Next Steps

- Observe and balance the representative SpeciesEcology profile set in runtime
- Observe and tune composed Phase 8 rhythms in the live runtime, then add one
	proven resource/rest semantic serving currently unsupported profiles
- Author additional map/tileset annotations only where blocked geometry is
	insufficient and source evidence is available
