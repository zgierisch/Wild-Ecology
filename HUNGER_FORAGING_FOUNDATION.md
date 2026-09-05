# Hunger And Foraging Foundation

## Scope

HUNGER is a normalized persistent drive introduced by save schema v6. It uses
existing drive hysteresis, utility competition, `SATISFY_NEED`, `SpatialGoal`,
ordinary WALK navigation, intent interruption, and `SETTLED` equilibrium.
There is no species-specific controller or hunger pathfinder.

Schema v6 preserves existing relationships, THIRST, FATIGUE, ecology identity,
and memory while deterministically adding only a HUNGER record to older
entities. Static feeding profiles, resolved hunger rates, selected goals,
feeding actions, and depletion state are not persisted.

## Feeding Vocabulary

SpeciesEcology exposes:

```lua
physiology = { hungerRate = 1.0 }
feeding = {
  acceptedOpportunityTypes = { "TALL_GRASS_FORAGE" }
}
```

`hungerRate` is resolved once through `EcologyPhysiology` for both live and
dormant updates. Feeding compatibility is biological profile data and never a
species branch in behavior.

`TALL_GRASS_FORAGE` is the only supported opportunity type. It interprets a
proven `TALL_GRASS` cell as coarse seed, insect, or vegetation-associated
foraging habitat. It does not assert literal grass consumption. Pidgey,
Rattata, and Caterpie accept this category. Species such as Goldeen, Geodude,
and Magnemite have persistent HUNGER but no currently realizable compatible
food opportunity.

Berries, flowers, fruit, nectar, prey, minerals, explicit resources, food
sharing, and cross-map discovery remain unsupported because WorldSemantics does
not currently prove those facts.

## Live Lifecycle

`FoodOpportunities.findNearby` performs a bounded semantic query only after
HUNGER becomes motivating. It normalizes compatible cells with a stable key:

```text
mapId:cellX:cellY:opportunityType
```

NeedStrategy proves an ordinary WALK route and returns the same generic need
opportunity shape used by THIRST. Arrival begins a 12-tick stationary feeding
action. Completion discharges HUNGER by 0.72, normally below its 0.20 release
threshold, and marks the local opportunity depleted for 300 ticks.

Depletion is transient process-local state separate from static world
semantics. It prevents immediate reuse without changing `TALL_GRASS` or
serializing a runtime goal. If another actor selected the same cell, concrete
goal identity invalidates its stale intent; ordinary deliberation may select a
different available opportunity. No reservation system or relationship is
created.

Emergency FLEE interrupts feeding through the existing purposeful-intent path.
THIRST, HUNGER, FATIGUE/REST, fear, and other behaviors continue to compete by
utility rather than fixed priority.

## Dormant Policy

Dormant cohorts store actor-scoped evidence:

```lua
opportunityEvidence = {
  THIRST = { [entityId] = evidence },
  HUNGER = { [entityId] = evidence }
}
```

Evidence is captured only when the compatible semantic opportunity and an
ordinary WALK route are conservatively proven at unload. Navigation is never
called during catch-up. Dormant HUNGER accumulates analytically using the same
resolved `hungerRate` as live simulation. Coarse offscreen satisfaction is
permitted only from captured evidence and never fabricates a path, consumed
entity, prey event, berry, resource discovery, or social interaction.

The old `reachableWater` capture option is accepted only as an input
compatibility bridge and immediately normalized to actor-scoped THIRST
evidence. Cohorts no longer store water-specific fields.

## Extension Path

Future food types should begin as explicit WorldSemantics facts, then add a
normalized opportunity definition and validated SpeciesEcology compatibility.
Explicit renewable resources may later replace transient depletion with a
persistent population-owned resource model. Predation requires its own entity
interaction and lifecycle design and is not part of this foundation.
