# Composed Daily-Rhythm and Long-Horizon Ecology Audit

## Scope and Result

This milestone proves that existing Phase 8 systems compose into understandable
long-horizon behavior without a timetable, agenda, behavior queue, routine
manager, or new physiological drive. The proof is deterministic active/local
simulation. It does not claim exact live-game balance, richer resource
semantics, or detailed dormant replay.

The initial hypothesis was that production architecture already had every
required owner. That was mostly true, but the first unmodified two-day run
exposed two generic `SATISFY_NEED` execution defects. After those corrections,
no routine-continuity abstraction or durable fact was needed.

## Harness

`tests/support/daily_rhythm_harness.lua` is test-only. It advances the real
`Controller.tick` on the 15-tick deliberation cadence and
`Controller.executeCurrentIntent` between deliberations. It applies emitted
WALK destinations, supplies real `WorldSemantics`, and can invoke production
concealment/emergence lifecycle seams.

The harness does not select behavior. It observes:

- ticks and occupancy by behavior;
- transitions and episode durations;
- drive minima, maxima, and satisfactions;
- home-return entries;
- concealment intervals;
- emergency interruptions;
- a bounded transition timeline.

Drive diagnostics read existing records directly. An early harness version
called the mutating drive status API while hidden; this changed recovery timing
and was corrected before results were accepted.

## Primary Two-Day Scenario

The primary scenario ran one Pidgey for 14,400 simulation ticks, with a
7,200-tick day, on a 14-by-3 local map containing:

- a stable radius-two home area;
- proven `TALL_GRASS_FORAGE` cells;
- reachable `WATER_ADJACENT` land;
- Pidgey-compatible tall-grass rest/concealment;
- ordinary open WALK space.

Measured occupancy:

| Behavior | Share |
|---|---:|
| `SETTLED` | 90.6% |
| `TARGET` | 2.5% |
| `SATISFY_NEED` | 2.0% |
| `RETURN_HOME` | 1.3% |
| `CONCEALED` | 1.2% |
| visible `REST` transition/travel | 0.1% |

There were 123 transitions, about 61.5 per simulated day. Transitions were
purposeful episodes separated by long calm spans rather than threshold chatter.
Both HUNGER and THIRST discharged repeatedly. FATIGUE rose meaningfully, REST
recovered it, concealed actors woke through canonical recovery, waited hidden,
and emerged legally without disturbance. Home return occurred repeatedly but
occupied little time and did not imply REST.

Representative transition excerpt:

```text
tick 30    SETTLED -> RETURN_HOME
tick 45    RETURN_HOME -> SETTLED (inside area)
tick 885   SETTLED -> SATISFY_NEED (THIRST)
tick 900   SATISFY_NEED -> SETTLED (water reached/discharged)
tick 930   SETTLED -> RETURN_HOME
tick 1515  SETTLED -> SATISFY_NEED (HUNGER)
tick 1530  SATISFY_NEED -> SETTLED (forage completed/discharged)
```

This is an observation, not an asserted order. Tests require broad occupancy,
multiple motivations, discharge, bounded transitions, home participation, and
normal concealed wake/emergence.

## Representative Variants

### Circadian and Species

Matched Pidgey and Rattata actors used the same opportunity layout. Existing
`CircadianSystem` output made Pidgey more active around the broad diurnal peak
and Rattata more active around the broad nocturnal peak. No exact hour or phase
transition selects behavior.

A one-day Rattata run completed HUNGER and THIRST cycles, included REST, and
spent 87.7% of observed time in `SETTLED`. Zubat with extreme FATIGUE used
visible in-place REST because cave walls/ceilings are not executable semantics;
it recovered and returned to `SETTLED`. Magnemite retained its weak-circadian
profile and unsupported HUNGER rather than receiving fabricated food.

Two Rattata individuals retained the same `NOCTURNAL` species profile while
existing persistent phase offsets and independence produced modestly different
exact circadian and home-return pressure. No randomness or schedule jitter was
added.

### Home, Scarcity, and Equilibrium

An actor without `home.area` never selected `RETURN_HOME`, while drinking and
other ecology remained functional. A hungry Magnemite with no compatible food
kept high HUNGER, performed other stable behavior, and did not fabricate an
opportunity. Planning remained cadence/bounds driven rather than becoming a
per-tick search loop.

The high `SETTLED` shares demonstrate that resources do not create chores and
healthy actors commonly remain stationary. Repeated need cycles discharge below
release thresholds and do not immediately reactivate.

### Social and Emergency Interruption

A trusted associate caused ordinary `APPROACH`. Once that bounded social episode
completed, severe THIRST won normal utility reevaluation. Sociality therefore
alters a day without monopolizing it.

A severe direct threat interrupted an active HUNGER episode with ordinary
`FLEE`. After threat and fear evidence cleared, the controller's first ordinary
choice rediscovered `SATISFY_NEED` because HUNGER remained high. Feeding then
completed and the actor settled. No previous/queued/next activity field exists.

Existing concealment disturbance tests separately prove weak disturbance may
leave sleep intact, moderate disturbance can wake while hidden, and strong
threatening disturbance can request emergence and seed generic FLEE.

## Problems Found and Corrections

1. Active `SATISFY_NEED` episodes invalidated during execution-only ticks because
   `IntentEpisode` could not see the already-retained transient opportunity.
   `Controller` now exposes `runtimeState.needOpportunity` to execution-only
   intent observation. No new state was added.
2. Production contexts enable locomotion pacing, but `LocomotionPolicy` omitted
   `SATISFY_NEED` from locomotor behaviors. Need tests had implicitly disabled
   pacing, masking the live-path freeze. The generic need behavior now uses its
   existing navigation under production pacing.
3. Test instrumentation initially mutated hidden drive timing by calling a
   status API. The harness now performs side-effect-free record reads.

No drive rates, utility weights, circadian profiles, home pressure, or species
profiles were tuned. The measured behavior did not justify such changes.

## Intent, Persistence, and Dormancy

Existing `IntentEpisode` commitment holds purposeful REST, needs, home return,
social travel, and FLEE across ordinary cadence ticks. Satisfaction,
invalidation, repeated execution failure, or a superior/emergency motive ends
or interrupts the episode. No long routine lock was introduced.

Schema remains v8. Existing persistence tests round-trip HUNGER, THIRST,
FATIGUE, circadian identity variation, home area/materialization coordinates,
and concealed location. Runtime intent, destinations, navigation, scores,
timelines, future tasks, and queues are stripped. Save/load therefore resumes
from durable ecology and reevaluates current context.

Dormant catch-up remains analytical and bounded to at most 48 temporal segments.
It advances drives/circadian context, preserves home and concealed state, and
never stores or replays a detailed daily sequence.

## Performance and Limits

Active work remains controller cadence/event driven. The harness and timeline
are test-only bounded diagnostics. No whole-map routine scans, activity-history
traversal, or per-tick planner were added.

Remaining limits:

- results are deterministic headless evidence, not live visual balance;
- only tall-grass forage and water adjacency are executable need resources;
- only tall grass is executable concealment;
- Zubat, Magnemite, Geodude, Goldeen, and other unusual profiles lack several
  biologically appropriate resource/rest semantics;
- no cross-map homing, schedules, predation, detailed dormant replay, or dynamic
  home relocation exists;
- repeated days vary only when existing environmental/social/individual context
  varies; no stochastic schedule jitter exists.

## Phase 8 Assessment

The deterministic exit-condition proof is now met for representative local
Pidgey/Rattata ecology: internal needs visibly produce feeding, drinking, REST,
roaming, concealment, and home return around substantial calm equilibrium.
Phase 8 should remain marked in progress until this composition is observed and
tuned in the live runtime and a broader set of species has executable resource
semantics.

The recommended next feature is broader proven resource semantics, beginning
with one non-tall-grass food/rest opportunity that benefits unusual existing
profiles without species-specific controllers. This follows directly from the
scarcity and unsupported-habitat evidence.
