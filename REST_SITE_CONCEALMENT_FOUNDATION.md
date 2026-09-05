# Rest-Site and Concealed-Rest Foundation

## Scope

This foundation extends the existing FATIGUE/REST path with bounded rest-site
choice, optional tall-grass concealment, generic disturbance response, and legal
rematerialization. It does not implement schedules, dens, nests, roosting,
aquatic traversal, predation, pursuit, battle mechanics, or cross-map execution.

## Previous Ownership Audit

Before this feature:

- `DriveDefinitions` defined persistent FATIGUE accumulation and REST recovery.
- `Utility.scoreBehaviors` combined FATIGUE pressure and circadian rest bias;
  terrain did not create motivation.
- `Controller` selected REST through the shared utility/hysteresis path.
- `states/rest.lua` stopped movement.
- `IntentEpisode` completed REST at the FATIGUE release threshold or a strong
  active-phase return below activation.
- `Drives.update` and `EcologyPhysiology.restRecovery` owned the only recovery
  equation for both live and dormant actors.
- `SETTLED` represented calm equilibrium, not physiological recovery.
- emergency threat selection interrupted REST through the existing FLEE path.
- `DormantCohortSimulator` handled FATIGUE analytically without navigation.
- `SpeciesEcology.restSites` was a validated ranked list inherited through
  fallback, archetype, and species overrides, but had no runtime consumer.
- `RuntimeAvatarAdapter` owned materialization, destruction, and normalized
  position reads; `RuntimeState.reset` discarded avatar-local execution state.
- ordinary perception was generated only from `activeAvatars` positions.
- proven WorldSemantics included `TALL_GRASS`, `OPEN_GROUND`, water adjacency,
  transitions, and explicitly authored annotations. Unknown barriers were not
  shelter, trees, caves, or vegetation.

REST remains its own purposeful behavior. It was not moved into SATISFY_NEED.

## Motivation Versus Location

REST motivation is still computed exclusively from FATIGUE, circadian bias,
utility competition, hysteresis, and emergency interruption. `RestSiteResolver`
is called only after REST has won. Low FATIGUE nzext to excellent cover produces
no scan, no destination, and no movement.

Site choice answers where and how to rest. It never changes FATIGUE, utility, or
circadian state.

## Species Representation

`restSites` remains the existing ranked biological preference list. Its legacy
vocabulary includes `DENSE_COVER`, `ELEVATED_COVER`, `BURROW`, `CAVE_WALL`,
`ROCKY_COVER`, `AQUATIC_COVER`, and similar contexts. Those labels are not
silently mapped onto unknown collision art.

`concealmentSites` is a separate validated array describing contexts in which a
species may become locally hidden. The only executable value is currently
`TALL_GRASS`.

- Rattata and Caterpie inherit tall-grass concealment from their archetypes.
- Pidgey explicitly permits tall-grass concealment.
- Magnemite, Goldeen, Geodude, Zubat, and other unsupported profiles visibly
  rest in place rather than using biologically inappropriate grass cover.

Static `restSites` and `concealmentSites` are resolved from SpeciesEcology and
are never copied into persistent entities.

## Resolver and Scoring

`src/needs/rest_site_resolver.lua` scans at most a five-cell local radius. It
uses only normalized WorldSemantics and executable WALK landing checks. It does
not pathfind, move an actor, mutate FATIGUE, or access host/runtime objects.

A normalized candidate contains map, cell, semantic type, preference score,
concealment capability/kind, distance, and deterministic score. Current support
creates candidates only from proven `TALL_GRASS` for explicitly compatible
species.

Scoring is intentionally small: compatible cover receives a fixed preference
and distance subtracts cost. Stable cell coordinates break ties. An acceptable
current cell wins unless another candidate is meaningfully better.

Travel budget shrinks as fatigue rises:

- below 0.70: up to four cells;
- 0.70-0.79: up to two cells;
- 0.80-0.89: up to one cell;
- 0.90 or greater: no discretionary travel.

No candidate means visible REST in place. An unreachable candidate is rejected
through normal navigation state and bounded reconsideration; REST never depends
on finding ideal habitat.

## Visible and Concealed REST

REST travel uses `SpatialGoal.position` and `NavigationExecution` with owner
`REST`. Navigation remains responsible for how WALK movement occurs. Recovery
does not begin while traveling.

At arrival:

- unsupported or ordinary contexts remain visibly materialized and stationary;
- compatible tall grass may create a concealment request;
- the lifecycle destroys the avatar through `RuntimeAvatarAdapter`;
- movement claims are cleared;
- the entity receives durable concealed location state;
- `RuntimeState.reset` discards routes, handles, movement, perception, and
  disturbance execution state.

The persistent entity is unchanged. Identity, relationships, personality,
memory, and drives survive.

Concealed location state is plain data:

```lua
{
  kind = "CONCEALED",
  mapId = "ROUTE_1",
  concealmentType = "TALL_GRASS",
  anchorCell = { cellX = 4, cellY = 5 },
  enteredTick = 120,
  awareness = "ASLEEP",
  resting = true
}
```

The representation is not REST-specific; later threat hiding, nesting, denning,
or local vegetation retreat can reuse it without creating another avatar state.

Concealed recovery calls the same `Drives.update` REST context and the same
`EcologyPhysiology.restRecovery` multiplier as visible REST. Site quality does
not alter recovery rate.

## Perception

Ordinary visible perception reads only materialized avatars. A concealed actor
has no entry in `activeAvatars`, so it cannot produce a ghost visible contact or
an exact visible-cell observation. Other systems may inspect durable concealed
presence as weaker ecological context without treating it as a visible NPC.

## Disturbance

`src/world/disturbance.lua` normalizes generic events with kind, optional source
identity/position, intensity, radius, tick, duration, and threatening flag.
Spatial falloff is bounded by the event radius. Disturbance is evidence, not a
spawn command.

`Concealment.respond` combines local intensity with existing individual
boldness. Responses are deterministic:

- weak: remain asleep and concealed;
- moderate: wake while remaining concealed and expose a rustle/shake cue;
- strong: request emergence;
- severe and threatening: request emergence and seed the existing FLEE input.

Waking and emerging are separate transitions. Hidden awareness can become
`AWAKE` while no runtime avatar exists.

Cues are transient domain records (`SUBTLE_RUSTLE`, `MODERATE_SHAKE`, or
`STRONG_SHAKE`) with anchor and expiry tick. They are actor-rate-limited to one
per 30 ticks and are not persisted or continuously randomized.

Player cell movement emits a modest generic `ACTOR_MOVEMENT` disturbance. It
does not directly materialize actors. Other wild actors and environmental
systems can emit the same event shape later.

`BATTLE` is already a valid generic disturbance kind. The current
`battle_bridge.lua` has no reliable host battle-start/state event and its only
method returns `false`, so live battle hookup is deferred. Synthetic BATTLE
events prove spatial falloff, individual response variation, hidden waking,
cues, emergence requests, and relationship non-mutation without speculative
battle architecture or player ownership.

## Emergence

`src/world/emergence.lua` checks only the concealment anchor and its immediate
neighborhood. Candidates must be in bounds, WALK-landable, transition-free,
connected by a legal adjacent WALK edge, and unoccupied. Open ground is
preferred deterministically over remaining in cover.

Successful emergence calls `RuntimeAvatarAdapter.materialize` and receives a
fresh runtime avatar. It then clears durable concealment and creates a fresh
RuntimeState. The old runtime handle is never reused.

If no legal cell exists or materialization fails, the entity remains concealed
and retries only on a later cadence/event. It is never overlapped, teleported,
or discarded.

A severe threatening disturbance seeds transient fear and last-known source
geometry after emergence. The shared controller may then select ordinary FLEE;
there is no concealment-, grass-, or battle-specific flee state.

## Persistence and Dormancy

Schema v7 introduced optional durable `locationState`. Current schema v8 adds
local home-area ecology while preserving every v7 concealment field. The v7
migration preserves every v6
identity, relationship, HUNGER, THIRST, FATIGUE, personality, and clock field.
Invalid non-concealed legacy location records are discarded.

Persisted:

- concealed versus visible local presence;
- map, concealment type, anchor, entered/wake tick;
- asleep/awake and resting state;
- existing drives and relationships.

Not persisted:

- runtime avatar or handle;
- REST destination or navigation route;
- resolver candidates;
- movement claims;
- disturbance events/effective impulses;
- cue animations;
- emergence attempts;
- perception contacts;
- static SpeciesEcology preferences.

Loading a concealed actor does not materialize it. Active-map lifecycle updates
coarse concealed recovery on the normal 15-tick cadence or when a disturbance
arrives. Detailed offscreen site travel, rustling, disturbance, and emergence
are never fabricated. Existing dormant FATIGUE simulation remains analytical.

## Nonplayable Fringe Seam

The generic location record can represent a future authored local fringe or
nonplayable vegetation concealment type. No such semantic is currently proven,
so this implementation does not infer tree lines from map edges, out-of-bounds
cells, unknown barriers, connections, warps, or doors. Adding the first fringe
consumer requires an explicit WorldSemantics annotation and a validated local
entry/emergence rule, not WorldTopology transition reuse.

## Diagnostics and Performance

`EcologyInspector.actor` now reports compact REST and CONCEALMENT lines:
motivation/state, selected context, candidate count, travel budget, resting,
location kind/type/anchor, awareness, and avatar expectation. It emits no
continuous log.

Resolver work is bounded to an 11-by-11 maximum neighborhood and runs only when
REST first needs a site or a candidate invalidates. Concealed lifecycle work is
limited to the current map and runs every 15 ticks unless queued disturbance
requires immediate evaluation. Disturbance queues cap at 32 events. Emergence
checks at most the anchor neighborhood. Concealed actors never pathfind.

## Current Limits

- Only proven tall grass is executable concealment.
- Legacy shelter, burrow, rocky, cave, aquatic, elevated, and powered rest
  preferences remain declarative.
- No SWIM, FLY, CLIMB, tree-roost, ceiling, or special traversal executor.
- No authored local tree-line/fringe semantic yet.
- No live battle event hookup.
- No rest quality, resource depletion, group sleeping, nest/den/home ownership,
  favorite-bed memory, daily schedule, predation, pursuit, or cross-map hiding.
- Presentation consumes cue records later; this foundation does not add a grass
  renderer animation.

The recommended next ecology feature is home-return and local home-anchor choice
using the same motivation-versus-location separation, without adding fixed daily
schedules.
