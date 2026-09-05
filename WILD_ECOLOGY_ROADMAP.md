# Wild Ecology — Revised Development Roadmap

## Why this roadmap replaces the original handoff roadmap

The project has moved beyond proving that visible wild Pokémon and relationships are possible.

A base spawning system now exists, along with a base relationship/trust/fear system. The roadmap should therefore focus on building the simulation in dependency order rather than continuing to mix proof-of-concept work, architecture, ecology, and content expansion together.

> We are no longer proving that wild Pokémon and relationships are possible. We are building the machinery that lets those systems produce believable behavior.

## Roadmap Summary

| Phase | Focus | Exit Condition |
|---|---|---|
| 3 | Persistent population identity | Returning to an area can produce the same individual Pokémon with preserved state |
| 4 | Perception & interaction events | Pokémon can observe entities/actions and update state generically |
| 5 | Behavior decision engine | Pokémon choose between idle, wander, flee, investigate, approach, etc. from internal state |
| 6 | Social behavior | Pokémon form groups and react to one another rather than only to the player |
| 7 | Environment & spatial understanding | Pokémon understand water, grass, shelter, territory, boundaries, etc. |
| 8 | Needs & daily behavior | Resting, drinking, foraging, roaming, and home-return behavior emerge |
| 9 | Species ecology profiles | Species become observably different without bespoke AI for every Pokémon |
| 10 | Relationship development & voluntary joining | Trust/affinity produces tolerance, approach, following, and eventually voluntary capture |
| 11 | Population lifecycle | Capture/removal, replenishment, migration, evolution, and population stability |
| 12 | Simulation performance & persistence hardening | Large populations work without save bloat or expensive AI |
| 13 | Compatibility/API layer | Other mods can interact without becoming dependencies |
| 14 | Balance, debugging tools & release | Systems are tunable, understandable, testable, and ready for normal players |

# Phase 3 — Persistent Population Identity

This should be the current phase.

The goal is not merely "persistent spawns." It is to establish that the world contains individual Pokémon independent of whether they are currently visible.

A route should effectively have a local persistent population:

```text
Route 1 Population

Pidgey     R1-0001
Pidgey     R1-0002
Rattata    R1-0003
Pidgey     R1-0004
Rattata    R1-0005
...
```

Entering Route 1 chooses a subset of those individuals. Leaving destroys their runtime representations. Returning may select some of the same individuals again.

Those Pokémon retain:

```text
entity ID
species
level
personality seed
relationship data
possibly home area
possibly group membership
```

Phase 3 should not yet care much about whether they drink, herd, or like the player.

The key test is:

```text
See Pidgey R1-0007
→ interact with it
→ leave Route 1
→ return later
→ R1-0007 appears again
→ its relationship state is unchanged
```

Save schema/versioning should also be established here while the persistent record is still small.

### Phase 3 exit condition

- Wild Pokémon have stable persistent IDs.
- Runtime overworld objects are temporary representations of persistent entities.
- Leaving and returning to a route can produce the same individual.
- Relationship state survives map transitions.
- Persistent records are versioned and serializable.
- Population selection reuses existing individuals instead of regenerating every spawn from scratch.

# Phase 4 — Perception and Interaction Events

Before Pokémon can behave naturally, they need a common way of perceiving what happens around them.

The behavior system should not directly say:

```lua
if playerNearPokemon then
    fear = fear + 5
end
```

Instead, entities should observe generic events:

```text
Entity A observes:
    Entity B entered perception
    Entity B approached rapidly
    Entity B attacked Entity C
    Entity C fled from Entity B
```

Create an event vocabulary.

Initial examples:

```text
ENTITY_SEEN
ENTITY_LOST
ENTITY_APPROACHING
ENTITY_RETREATING
ENTITY_NEAR
ENTITY_ATTACKED
ENTITY_FLED
ENTITY_RESTING
ENTITY_FEEDING
ENTITY_FOLLOWING
ENTITY_IN_COMBAT
```

Later environmental events can include:

```text
FOOD_FOUND
WATER_FOUND
THREAT_FOUND
SHELTER_FOUND
```

This becomes the sensory language of the AI.

Relationship updates then consume those observations.

```text
unknown entity approaches quickly
        ↓
temporary fear rises

same entity repeatedly remains nearby peacefully
        ↓
familiarity rises
trust rises slightly

trusted Pokémon flees from entity X
        ↓
observer becomes more suspicious of X
```

### Phase 4 exit condition

Two Pokémon and the player can all generate and respond to the same generic observations.

The relationship system is demonstrably entity-centric rather than player-centric.

# Phase 5 — Behavior Decision Engine

Now build the actual decision system.

A utility system is preferable to a giant state machine where every state manually transitions to every other state.

Each possible behavior receives a score:

```text
FLEE                84
APPROACH_ASSOCIATE  61
INVESTIGATE         47
REST                32
WANDER              15
```

The Pokémon chooses an appropriate high-scoring behavior and retains it for a reasonable amount of time.

Initial behavior set:

```text
IDLE
WANDER
ALERT
FLEE
INVESTIGATE
APPROACH
FOLLOW
RETURN_HOME
```

Important inputs:

```text
temperament
relationships
nearby entities
distance
current fear/stress
recent events
current state
```

Examples:

- A timid unfamiliar Rattata may flee.
- A familiar Rattata may remain nearby.
- A curious Pikachu may investigate.
- A hostile Mankey may approach.

This is where the relationship system should become visibly meaningful.

### Hysteresis

Behavior must not oscillate every frame.

Avoid:

```text
wander
flee
wander
flee
wander
flee
```

Use:

- minimum state durations;
- cooldowns;
- score hysteresis;
- bounded randomness;
- lower-frequency decision ticks.

### FLEE planning cadence

FLEE motivation and high-level utility deliberation remain separate from movement
execution and route construction. High-level utility runs on its 15-simulation-tick
cadence (or a meaningful interrupt), while current-intent execution may run every
simulation tick. A missing route is data, not permission to invoke bounded planning.

Bounded FLEE planning uses these transient runtime states:

```text
LOCAL_STEERING
NEEDS_PLAN
FOLLOWING_ROUTE
WAITING_FOR_ROUTE_CELL
PLAN_BLOCKED_UNCHANGED
NEEDS_REPLAN
```

An unchanged blocked or statically rejected problem remains
`PLAN_BLOCKED_UNCHANGED`. Actor movement, watched blocker movement or replacement,
claim ownership changes, material threat movement/source changes, and map/topology
changes dirty the problem immediately. A 180-simulation-tick watchdog is a fallback,
not the normal cadence. The dirty check compares scalar context plus at most four
watched adjacent cells; it does not hash the occupancy map or reserve a whole route.

Planner calls, route objects, suppressed calls, and dirty-event causes are exposed by
the behavior debug snapshot.

### Phase 5 exit condition

The same external situation can produce different behavior depending on individual temperament, relationship state, recent events, and current internal state.

# Phase 6 — Social Behavior

Only after individual decision-making works should herding/flocking be added.

This phase proves that Pokémon meaningfully affect one another.

Implement:

```text
cohesion
separation
weak directional alignment
associate following
alarm propagation
social reassurance
```

Where possible, use the relationship model rather than a hard-coded herd mode.

A Pokémon does not necessarily need:

```lua
isHerding = true
```

to explain why it stays near others.

It can instead evaluate:

```text
I strongly prefer being near A and B.
I dislike being isolated.
I do not want to stand directly on top of them.
```

A group ID is still useful for spawning, neighbor lookup, performance, and population organization, but it should not be the entire explanation for social behavior.

### Social learning

```text
Pidgey A trusts Pidgey B.

Player scares B.

B flees.

A observes that B is afraid of the player.

A's perceived threat from player rises.
```

The inverse should happen more slowly:

```text
B calmly spends time near player repeatedly.

A sees this.

A gradually becomes less suspicious.
```

### Phase 6 exit condition

- Pokémon form loose social groups.
- Individuals react to nearby associates.
- Fear can propagate socially.
- Calm behavior can produce slow reassurance.
- Player-directed reactions emerge from the same system as Pokémon-to-Pokémon reactions.

# Phase 7 — Environmental Understanding

Now give Pokémon meaningful places to go.

Build a semantic layer over map cells.

The AI should eventually be able to ask:

```text
Where is nearby water?
Where is the water edge?
Where is tall grass?
Where are paths?
Where is shelter?
Where are cliffs?
Where are walls?
Where are caves?
```

Do not immediately make every terrain type biologically meaningful.

First establish:

```text
Environment query
        ↓
semantic tags
        ↓
navigation target
```

Example:

```text
water tile
        ↓
find adjacent walkable cell
        ↓
WATER_EDGE
```

Now terrestrial Pokémon have a valid drinking destination.

### Zones and home areas

Avoid relying only on exact home coordinates:

```text
homeX = 37
homeY = 12
```

Prefer an area concept such as:

```text
Route 3
northwestern grass zone
```

That is more useful later for territories, population placement, home-return behavior, and migration.

### Phase 7 exit condition

- The environment can classify useful semantic locations.
- Pokémon can find valid targets such as water edges, grass, shelter, or home zones.
- Behavior code no longer treats every walkable tile as equivalent.

# Phase 8 — Needs and Routine Behavior

This is where the simulation starts to look ecological.

**Current status:** foundation in progress. Generic persistent drive state,
threshold hysteresis, elapsed-tick accumulation, semantic opportunity
strategies, and the complete THIRST-to-`WATER_ADJACENT` lifecycle are
implemented. The Ecology Clock, smooth circadian profiles, persistent FATIGUE,
purposeful REST, and bounded dormant-cohort catch-up foundations are also in
place. The HUNGER/foraging foundation now completes motivation, compatible
`TALL_GRASS_FORAGE` selection, ordinary WALK travel, bounded feeding, local
depletion, discharge, and equilibrium. The REST-site/concealed-REST foundation
now adds motivation-gated local site choice, fatigue-limited WALK travel,
visible fallback, compatible `TALL_GRASS` concealment, generic disturbance,
hidden waking, transient rustle cues, and bounded legal emergence. The LOCAL
HOME foundation now adds stable persistent areas, deterministic
legal establishment, species/individual roaming tendency, circadian-sensitive
utility, generic WALK navigation to any acceptable area cell, and ordinary
equilibrium after satisfaction. Deterministic one- and two-day active
simulations now prove that these independent systems compose into repeated
drinking, foraging, REST, concealment, roaming, and home-return episodes around
substantial `SETTLED` occupancy without schedules or queued activities. The
proof exposed and corrected generic need-intent continuity and production-paced
need locomotion gaps. Live visual observation/tuning, richer resource ecology,
general concealment, dynamic relocation, and cross-map homing remain open, so
Phase 8 remains in progress rather than being declared complete.

Add only a small set of needs initially:

```text
thirst
hunger / forage drive
fatigue
social need
```

Possibly:

```text
security / stress
```

Each changes gradually.

Behaviors then compete:

```text
drink                 71
stay near herd        56
forage                48
rest                  31
wander                10
```

This can produce sequences such as:

```text
Tauros grazes
→ travels with herd
→ becomes thirsty
→ herd drifts toward water
→ drinks
→ rests nearby
```

without scripting a schedule.

### Important visual rule

Pokémon should spend a substantial amount of time doing nothing.

Natural-looking wildlife should not constantly pace. Resting, grazing, observing, and remaining stationary should occupy significant portions of activity.

### Phase 8 exit condition

Pokémon visibly alternate between meaningful activities because of internal needs rather than merely random movement.

# Phase 9 — Species Ecology Profiles

**Current status:** portability and profile foundations implemented. A
generation-neutral mechanics adapter, move-semantic option layer, bounded
physical phenotype, and validated fallback/archetype/species resolver now feed
eleven representative species across eight ecological archetypes. Runtime
observation, balancing, and broader Gen I coverage remain open, so Phase 9 is
not complete.

Only now should broad species tuning begin.

Do not write 151 separate AI controllers.

Create behavioral archetypes such as:

```text
small skittish forager
flocking bird
herd grazer
curious social animal
territorial animal
solitary predator
aquatic
shoreline
cave dweller
insect colony
stationary / plantlike
large solitary animal
supernatural / erratic
```

Then species inherit an archetype and override parameters.

```lua
PIDGEY = {
    archetype = "flocking_bird",

    sociability = 0.85,
    fearfulness = 0.65,
    curiosity = 0.25,
    territoriality = 0.10,
}
```

```lua
SPEAROW = {
    archetype = "flocking_bird",

    sociability = 0.70,
    fearfulness = 0.35,
    aggression = 0.55,
    territoriality = 0.45,
}
```

Same core AI. Noticeably different animals.

### Representative test species

Do not tune all 151 immediately.

Start with a varied test set such as:

```text
Pidgey
Spearow
Rattata
Pikachu
Nidoran
Mankey
Ekans
Oddish
Paras
Psyduck
Magikarp
Tauros
Kangaskhan
Abra
Onix
Gastly
```

### Phase 9 exit condition

Representative species from different ecological/archetype groups behave observably differently without bespoke controller code for each species.

# Phase 10 — Relationship Development and Voluntary Joining

Return here to the philosophical centerpiece of the project.

By this stage the Pokémon should already be able to:

```text
recognize
observe
avoid
approach
follow
associate
learn socially
```

Voluntary joining then becomes an extension of the existing system rather than a separate capture mechanic.

Likely persistent relationship vocabulary:

```text
familiarity
trust
affinity
threatMemory
hostility
```

Immediate fear should remain mostly transient state.

### Behavioral progression

```text
flees immediately
↓
hesitates before fleeing
↓
remains nearby
↓
allows approach
↓
approaches trainer
↓
follows trainer briefly
↓
seeks trainer out
↓
follows toward route exit
↓
willing to join
```

The progression is more important than a numeric threshold.

The player should notice the relationship changing through behavior rather than only through a meter.

### Joining

Once a Pokémon chooses to join:

```text
no battle
no catch RNG
no failure roll
```

It voluntarily enters a Poké Ball or otherwise joins through the normal owned-Pokémon party/box pipeline.

Traditional capturing remains intact.

### Phase 10 exit condition

A specific persistent wild Pokémon can progress from unfamiliar/fearful to trusting, affiliative, following, and voluntarily joining the trainer without any player-specific friendship subsystem.

# Phase 11 — Population Lifecycle

Until this point, route populations can remain mostly static.

Now solve longer-term population behavior.

Questions include:

```text
What happens when one is captured?
How is the population replenished?
Can Pokémon move between adjacent areas?
Do levels change?
Can wild Pokémon evolve?
Do groups gain or lose members?
Can individuals disappear permanently?
```

Reproduction does not need to be explicitly simulated.

A population manager can replenish vacancies abstractly:

```text
Route population target: 24
Current population: 21
        ↓
eligible replenishment window
        ↓
generate 2–3 new individuals
```

Migration between connected areas may later allow an individual to occasionally appear in an adjacent route.

Do not implement large-scale migration until local populations are reliable.

### Phase 11 exit condition

The persistent world remains stable as Pokémon are captured, removed, added, or eventually moved between habitats.

# Phase 12 — Performance and Persistence Hardening

This should be a dedicated phase, not end-of-project cleanup.

By now the save may contain hundreds or thousands of persistent individuals.

Establish simulation levels:

```text
near player
    full AI

farther on current map
    reduced AI

not on current map
    no runtime simulation
```

Optional later:

```text
offscreen coarse simulation
```

but only if the design actually needs it.

Address:

```text
relationship pruning
save size
population serialization
schema migration
spatial lookup
AI tick frequency
environment cache
pathfinding load
```

### Relationship pruning

A Pokémon does not need permanent memory of every entity it briefly encountered.

Keep:

- close associates;
- repeated companions;
- significant threats;
- trainer relationships;
- strong rivals.

Allow insignificant relationships to decay or be removed.

### Phase 12 exit condition

The simulation can support large persistent populations without unacceptable frame cost, save size, load time, memory use, or relationship-table growth.

# Phase 13 — Compatibility and Public API

Only after the simulation stabilizes should integration be formalized.

Potential future capabilities:

```text
getWildEntity()
getVisibleWildEntities()
getRelationship()
notifyInteraction()
registerVisualProvider()
registerEnvironmentProvider()
registerBehaviorModifier()
```

Other mods could optionally provide:

```text
weather
alternate overworld sprites
3D models
followers
new species
new environmental data
new interactions
```

without becoming hard dependencies.

This is also the phase to handle explicit conflicts with other overworld-spawning mods.

### Phase 13 exit condition

Wild Ecology remains standalone but exposes narrow, stable integration points for other mods.

# Phase 14 — Balance, Debugging, and Release

Before public release, build tuning/debugging tools.

A debug overlay or inspection menu should expose values such as:

```text
entity ID
species
temperament
current behavior
behavior scores
needs
relationships
current target
home zone
group
perceived threats
```

Example:

```text
Pidgey R1-0007

State: ALERT

Player
 familiarity 62
 trust       31
 affinity     8
 threat      12

Decision:
 FLEE        42
 WANDER      13
 APPROACH     5
 REST         2
```

This is essential for understanding why behavior looks wrong.

These values do not necessarily belong in the normal player UI. For ordinary play, the Pokémon's behavior should communicate most of the relationship state.

### Phase 14 exit condition

- Major behavior parameters are tunable.
- Debugging tools make decisions inspectable.
- Save migrations are tested.
- Performance is profiled.
- Compatibility constraints are documented.
- Normal players do not need debug information to understand basic Pokémon reactions.
- The mod is ready for broader release/testing.

# Project-Level Milestones

The phase numbers are useful, but three larger milestones determine whether the project is actually succeeding.

## 1. Simulation Milestone

Pokémon behave differently because of internal state and surroundings rather than merely wandering randomly.

This requires:

- persistent individual state;
- perception;
- behavior decisions;
- environmental context.

## 2. Social Milestone

Pokémon meaningfully react to one another, and the player is demonstrably processed through the same relationship/perception system.

This requires:

- generic entity relationships;
- group behavior;
- social fear propagation;
- reassurance/social learning;
- no special `trustWithPlayer` logic.

## 3. Relationship Milestone

A specific wild Pokémon can move from unfamiliar and fearful to voluntarily following and joining the trainer without any special player-only friendship code.

This proves the central design idea works.

# Immediate Direction for Phase 3

Phase 3 should **not** become "implement more spawning features."

It should specifically convert the existing spawning system into a persistent population and identity layer.

The immediate work should focus on:

1. Stable entity IDs.
2. Persistent route population pools.
3. Runtime avatars linked to persistent IDs.
4. Re-selecting existing individuals on later visits.
5. Preserving relationship state.
6. Save schema/versioning.
7. Removing runtime-object ownership from persistent simulation state.

Only after that foundation is reliable should the project move into perception and behavior expansion.

# Guiding Principle

The project should continue to follow this dependency order:

```text
Identity
    ↓
Perception
    ↓
Decision-making
    ↓
Social behavior
    ↓
Environmental understanding
    ↓
Needs
    ↓
Species differentiation
    ↓
Relationship development
    ↓
Voluntary joining
    ↓
Population lifecycle
    ↓
Performance
    ↓
Compatibility
    ↓
Release
```

Each phase should leave behind a working, testable system that the next phase can build on.
