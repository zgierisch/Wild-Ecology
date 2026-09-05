# AGENTS.md

## Purpose

This repository implements Wild Ecology, a standalone Gen1Recomp mod for
persistent wild Pokemon, visible overworld populations, naturalistic behavior,
generic entity relationships, social learning, and future voluntary joining.

Primary references:

- `ARCHITECTURE.md`
- `WILD_ECOLOGY_ROADMAP.md`
- `ASSETS.md`
- `quedonde-README.md`
- relevant current Gen1Recomp source and documentation

## Core Invariants

1. The player is a normal entity target in the relationship graph. Do not add
   player-only relationship fields.
2. Persistent entities are authoritative and runtime avatars are disposable.
   Never serialize runtime engine objects.
3. Relationships are sparse and directed. Do not build all-to-all matrices.
4. The mod remains standalone. Do not add hard gameplay-mod dependencies.
5. Reference mods are references, not API contracts.
6. Voluntary joining must end in the normal owned-Pokemon pipeline.
7. Species behavior is archetype plus parameters, temperament, and context.
   Avoid species-specific AI controllers.

## Source of Truth

1. Repository code and tests
2. `ARCHITECTURE.md`
3. Current Gen1Recomp source and documentation
4. Public API definitions and examples
5. Reference mods
6. External discussion

## Search Workflow

Use `quedonde.py` for connection-style architecture questions and direct symbol
search for concrete symbols. Before the first `quedonde.py` use in a session:

1. Read `quedonde-README.md`.
2. Run the documented setup and index commands.
3. Validate results against source files directly.

The bundled Lua index is not a complete call graph; direct reference searches
remain required.

## Roadmap Discipline

The authoritative phase list and incomplete work are in
`WILD_ECOLOGY_ROADMAP.md`. Do not implement future-phase features unless a
current contract requires the boundary.

Joining, battle integration, population lifecycle, persistence/performance
hardening, and a public compatibility API remain deferred. Their old source
placeholders were not implementations.

## Engine Boundary

Keep engine-facing logic isolated in existing adapters such as:

- `src/world/runtime_avatar_adapter.lua`
- `src/world/avatar_factory.lua`
- `src/world/environment.lua`

Keep persistence, entities, relationships, and ecology state as plain Lua data
where possible.

Gen1Recomp is an immutable runtime dependency:

- Inspect engine source and use documented public APIs.
- Use narrowly isolated `engine_internals` access only when a required stock
  runtime operation has no public API.
- Do not edit, fork, rebuild, install, or require a custom Gen1Recomp build.
- Keep internal requires and runtime-object mutation inside world/avatar seams.
- Ordinary movement uses stock collision-authoritative `WALK`; never fall back
  to collision-skipping `scriptMove`.

Persistent entities survive avatar destruction. Runtime state does not.
Transient state includes live NPC references, map-local motion data, queued
commands, rejection/perception caches, target coordinates, and pathfinding
results. Clear it on destruction or reconstruction, then observe and deliberate
again. Identity, temperament, sparse relationships, long-term memory, drives,
location/concealment, and population/home records may persist as plain data.

## Persistence

Use `mod.storage` through the Gen1 persistence adapter. Preserve save schema
versioning and migrations when durable shapes change. Never store runtime NPC
objects, functions, engine userdata, or an in-progress avatar command.

## Testing

Add deterministic tests at the lowest practical layer. Run specs in fresh Lua
processes, and do not claim a test passed unless it was executed. Headless and
fake-adapter coverage does not prove full live-engine behavior.

## Stop Conditions

Stop and report if a change would:

- make the player a special relationship target;
- serialize runtime objects;
- create a hard mod dependency;
- require broad engine changes without a validated boundary; or
- break save compatibility without migration.