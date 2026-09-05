# AGENTS.md

## Purpose

This repository implements Wild Ecology, a standalone Gen1Recomp mod for persistent wild Pokemon, visible overworld populations, naturalistic behavior, generic entity-to-entity relationships, social learning, and an eventual voluntary-joining path.

This file is the operating guide for coding agents working in this repository.

Primary references:
- gen1recomp_wild_ecology_handoff.md
- quedonde-README.md
- Current Gen1Recomp source/docs
- Gen1PC-OverworldEncounters as reference only (never a dependency)

## Core invariants

1. Player is a normal entity target in the relationship graph.
- Do not add player-only relationship fields.

2. Persistent entity is authoritative, runtime avatar is disposable.
- Never serialize runtime engine objects.

3. Relationships are sparse and directed.
- Do not build all-to-all matrices.

4. Mod remains standalone.
- No hard dependency on other gameplay mods.

5. Reference mods are references, not API contracts.

6. One owned-Pokemon pipeline.
- Voluntary joining must end in normal ownership flow.

7. Species behavior is archetype + parameters + temperament + context.
- Avoid species-by-species hardcoded AI.

## Source-of-truth order

1. Repository code and tests
2. gen1recomp_wild_ecology_handoff.md
3. Current Gen1Recomp source/docs
4. Public API definitions/examples
5. Reference mods
6. External discussion

## Required search workflow

Use quedonde.py for connection-style architecture questions and direct symbol search for concrete symbols.

Before first quedonde.py use in a session:
1. Read quedonde-README.md
2. Run required setup/index steps
3. Validate results against source files directly

## Roadmap discipline

Authoritative phase list (WILD_ECOLOGY_ROADMAP.md, supersedes any older numbering):
- Phase 3: persistent population identity
- Phase 4: perception & interaction events
- Phase 5: behavior decision engine
- Phase 6: social behavior
- Phase 7: environmental understanding
- Phase 8: needs & routine behavior
- Phase 9: species ecology profiles
- Phase 10: relationship development & voluntary joining
- Phase 11: population lifecycle
- Phase 12: simulation performance & persistence hardening
- Phase 13: compatibility/API layer
- Phase 14: balance, debugging tools & release

Do not implement future-phase features unless required by current phase seams.

## Engine boundary rule

Keep engine-facing logic isolated in adapters such as:
- src/world/avatar_factory.lua
- src/world/environment.lua
- src/interaction/battle_bridge.lua

Keep persistence/entities/relationships as plain Lua data where possible.

Gen1Recomp is an immutable runtime dependency.
- Allowed: inspect engine source, use documented public APIs, and use narrowly isolated `engine_internals` access when the public API cannot express a required stock-runtime operation.
- Not allowed: edit, fork, rebuild, install, or require a custom Gen1Recomp build.
- Keep internal requires and runtime-object mutation inside world/avatar adapters only.
- Ordinary WALK movement may use stock `src.world.Collision` and NPC state through the declared permission; never fall back to collision-skipping `scriptMove`.

Persistent entity survives avatar destruction.
- Runtime/avatar state never survives avatar destruction.
- Any state containing live NPC references, map-local movement data, motion execution, rejection caches, perception contacts, target coordinates, or pathfinding results is transient.
- Reset transient runtime state when an avatar is destroyed or reconstructed; then re-observe and reevaluate behavior.
- Persistent records may retain identity, species, temperament, relationships, long-term memory, and population/home identity, but never an in-progress avatar command.

## Persistence rules

Use mod.storage for persistent data.
Include save schema versioning and migrations when shape changes.
Never store runtime NPC objects, functions, or engine userdata.

## Testing expectations

Each phase adds deterministic tests at the lowest practical layer.
Do not claim tests passed unless actually executed.

## Stop conditions

Stop and report if a change would:
- make player a special relationship target,
- require serializing runtime objects,
- create hard mod dependency,
- require broad engine changes without validated seam,
- break save compatibility without migration.

## Current milestone

Phase 3 (persistent population identity) is met: stable entity IDs, disposable
runtime avatars, deterministic visible-subset selection, persisted spawn
cells, relationship state surviving map transitions, versioned/serialized
population records. Phase 4 (generic perception/interaction events) and
Phase 5 (utility-scored behavior decision engine with hysteresis) are also
substantially implemented (src/world/perception.lua, src/behavior/utility.lua
+ controller.lua). Phase 6 (social behavior) is met: associate following,
generic fear/reassurance propagation (any trusted associate, any target --
src/population/manager.lua's propagateAssociateSocialSignal), crowding guard,
and weak directional alignment (ambient wandering nudges toward nearby
trusted associates' recent heading) are all implemented.

Phase 7 environmental semantics are implemented. Phase 8 remains in progress:
THIRST, HUNGER/foraging, FATIGUE/REST, concealed rest, local HOME/RETURN_HOME,
and deterministic composed daily-rhythm proofs exist without schedules or
queues. Live observation/tuning and broader executable resource semantics
remain. Phase 11 population lifecycle (capture/removal/replenishment/migration)
has not started.

Partial: Phase 9 (species ecology profiles cover eleven representative species
across eight validated archetypes; runtime observation, balancing, and broader
Gen I coverage remain), Phase 10 (voluntary_join.lua has a threshold check but
isn't wired into the real owned-Pokemon pipeline), Phase 12 (save
versioning exists, no large-population perf hardening), Phase 13
(compat/exports.lua is a bare ping() stub).

Current focus: live Phase 8 rhythm observation, broader resource/rest
semantics for unsupported profiles, Phase 9 profile expansion, and Phase 14
debugging tooling.


