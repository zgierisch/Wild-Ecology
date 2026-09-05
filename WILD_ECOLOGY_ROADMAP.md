# Wild Ecology Roadmap

This roadmap tracks incomplete and future work. Current implemented contracts
belong in [ARCHITECTURE.md](ARCHITECTURE.md). Existing phase numbers remain
stable because they are also used by configuration, diagnostics, and tests.

## Status Summary

| Phase | Focus | Status |
| --- | --- | --- |
| 3 | Persistent population identity | Implemented foundation; see [persistence and reconstruction](ARCHITECTURE.md#3-persistence-and-reconstruction) |
| 4 | Perception and interaction events | Implemented foundation; see [relationship and event ownership](ARCHITECTURE.md#4-relationship-and-event-ownership) |
| 5 | Behavior decision engine | Implemented foundation; see [scheduling, behavior, and motion](ARCHITECTURE.md#5-scheduling-behavior-and-motion) |
| 6 | Social behavior | Implemented foundation; see [relationship and event ownership](ARCHITECTURE.md#4-relationship-and-event-ownership) |
| 7 | Environment and spatial understanding | Implemented foundation; see [world semantics](ARCHITECTURE.md#7-world-semantics) |
| 8 | Needs and routine behavior | In progress |
| 9 | Species ecology profiles | In progress |
| 10 | Relationship development and voluntary joining | Future integration |
| 11 | Population lifecycle | Future |
| 12 | Performance and persistence hardening | Future |
| 13 | Compatibility and public API | Future |
| 14 | Balance, debugging, and release | In progress |

## Phase 8: Needs and Routine Behavior

The persistent THIRST, HUNGER, FATIGUE, REST, compatible concealment, local
home-area, `RETURN_HOME`, ecology clock, circadian, and bounded dormant-catch-up
foundations are implemented. Home return, hunger, and navigation are not
missing foundations.

Remaining work:

- observe and tune composed daily rhythms in the live runtime;
- broaden executable food and rest semantics for profiles that currently lack
  a compatible proven opportunity;
- tune stationary occupancy so wildlife does not constantly pace;
- improve resource ecology and concealment only where world evidence supports
  it; and
- retain schedule-free utility competition rather than adding agendas or
  behavior queues.

Cross-map homing, territory, dynamic relocation, and scripted schedules are not
implemented.

## Phase 9: Species Ecology Profiles

The validated fallback, ecological archetype, and species-override layers are
implemented for a representative profile set. Mechanics, temperament, and
species ecology remain separate.

Remaining work:

- observe and balance representative profiles in the live runtime;
- expand profile coverage across Gen I without bespoke controllers;
- add archetypes only when multiple species need a coherent new composition;
  and
- retain data-only authoring and strict validation.

## Phase 10: Relationship Development and Voluntary Joining

Build visible progression from avoidance through tolerance, approach, and
following. A trusted persistent wild Pokemon may eventually choose to join, but
joining and battle ownership are not currently wired.

The result must enter the normal owned-Pokemon party/box pipeline and preserve
ecology as sidecar data rather than creating a second Pokemon ownership model.
Traditional capture remains intact. The old voluntary-join and battle bridge
source placeholders were removed because they did not implement these
integrations; declarative species join thresholds remain.

## Phase 11: Population Lifecycle

Implement durable consequences for capture/removal and bounded replenishment.
Later work may add migration between connected habitats, level development,
evolution, and group membership changes without simulating reproduction in
detail.

Identity across capture, evolution, and trade is a requirement, not an
implemented feature. Any owned Pokemon must continue to use the normal engine
record with Wild Ecology state retained as a sidecar.

## Phase 12: Performance and Persistence Hardening

Measure and harden large persistent populations without changing behavior
blindly. Remaining work includes:

- save size, snapshot cost, serialization cadence, and migration testing;
- relationship pruning that preserves significant associates, threats,
  trainers, and rivals;
- spatial lookup and environment-cache costs;
- AI scheduling and pathfinding load; and
- bounded near/current-map/off-map simulation levels where evidence justifies
  them.

Do not treat this documentation cleanup as permission to perform pending
performance optimization.

## Phase 13: Compatibility and Public API

Define a real narrow API only after simulation contracts stabilize. Candidate
capabilities include querying persistent/visible entities and relationships,
notifying interactions, and registering visual, environment, species, or
behavior providers without hard dependencies.

The previous compatibility export placeholder was removed because it was not a
public API. Explicit coexistence rules for other overworld-spawning mods remain
future work.

## Phase 14: Balance, Debugging, and Release

Continue live observation, balancing, and diagnostics. Inspection should expose
entity identity, temperament, current behavior and scores, needs,
relationships, targets, home area, group context, and perceived threats without
making debug UI necessary for ordinary play.

Release work includes tuning major parameters, validating save migrations,
profiling representative workloads, documenting compatibility constraints, and
testing with normal players and the live engine.

## Guiding Constraints

- Preserve sparse directed relationships and generic player targeting.
- Preserve one normal owned-Pokemon pipeline with ecology as sidecar state.
- Keep runtime avatars and executable commands transient.
- Keep Gen1Recomp immutable and Wild Ecology standalone.
- Implement future work in dependency order and leave each phase testable.