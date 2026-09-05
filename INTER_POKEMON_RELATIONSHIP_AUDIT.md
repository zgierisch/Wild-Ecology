# Inter-Pokemon Relationship Audit

Date: 2026-08-22

## Scope and result

The persistent relationship data layer, directed identity ownership, save/re-entry path, and several behavior consumers work for Pokemon-to-Pokemon records. The system is not complete: some fields have no organic producer, some metadata has no behavioral consumer, and direct attack/flee event semantics are not emitted by the live overworld pipeline yet.

Two implementation defects were proven and fixed during this audit:

1. `Social.observeNearby` constructed a reduced relationship shape instead of using `Relationships.getOrCreate`. Pokemon-first records could omit `directThreatMemory` and calm-visit fields. Social contact now uses the canonical generic constructor.
2. `Save.flush` passed active entities directly to storage, including transient `runtimeState`. It now writes a deep persistence snapshot with population-member runtime state removed, without mutating the live simulation cache.

No new relationship-driven behavior was added.

## Production Producers

| Event / condition | Direction | Fields changed | Lifetime | Live status |
|---|---|---|---|---|
| Nearby Pokemon within 5 cells, `Social.observeNearby` | observer -> nearby Pokemon | `familiarity`, `affinity`, `lastSeenTick`, `importance` | Persistent | Live for every visible observer |
| First entry into perception, `ENTITY_SEEN` | observer -> subject | `familiarity`, `lastSeenTick` | Persistent | Live and edge-triggered |
| Within 2 cells, `ENTITY_NEAR` | observer -> subject | `familiarity`, `lastSeenTick` | Persistent | Live and level-triggered |
| Subject begins approaching | observer -> subject | `lastSeenTick`; observer `perceivedFear[subject]` | Mixed: timestamp persistent, Fear transient | Live and motion-edge-triggered |
| Subject begins retreating | observer -> subject | `lastSeenTick`; reduces `perceivedFear[subject]` | Mixed | Live and motion-edge-triggered |
| Subject leaves perception, `ENTITY_LOST` | observer -> subject | transient perceived-Fear relief only | Transient | Live and edge-triggered |
| Investigation episode completes | observer -> investigated subject | `familiarity` by bounded elapsed-time gain | Persistent | Live for generic selected targets |
| Calm proximity through `updatePhase0Relationship` | Pokemon -> player entity ID | `familiarity`, `trust`, reduced `threatMemory`, `lastSeenTick`; player trust floor | Persistent | Live, but orchestration is player-oriented |
| Trusted associate flees a target | observer -> associate target | raised `threatMemory`, reduced `trust`, `lastSeenTick` | Persistent | Live when social propagation option is enabled |
| Trusted associate approaches a target | observer -> associate target | reduced `threatMemory`, raised `trust`, `lastSeenTick` | Persistent | Live when social reassurance option is enabled |
| `ENTITY_ATTACKED` | victim/observer -> aggressor | `threatMemory`, `directThreatMemory`, `lastSeenTick`; runtime direct evidence | Mixed | Mutation API exists; no live overworld emitter found |
| `ENTITY_FLED` | observer -> subject | `threatMemory`, `lastSeenTick` | Persistent | Mutation API exists; no live overworld emitter found |
| Phase-0 debug overrides | anchor -> player | `trust`, `threatMemory`, `hostility` | Persistent debug mutation | Debug-only |

In the live inter-Pokemon loop, `SOCIAL_NEARBY` runs before the first `ENTITY_SEEN`. It is therefore the first relationship-creating production event for a newly perceived Pokemon pair.

No organic affinity loss, hostility gain/loss, or importance evolution beyond the nearby-contact floor was found.

## Production Consumers

| Consumer | Observer-owned fields read | Direction and effect |
|---|---|---|
| `TargetSelector` APPROACH ranking | `affinity`, `trust` | A ranks B from `A.relationships[B.id]`; higher values raise B's score |
| Utility APPROACH | `trust`, `affinity` | Raises A's APPROACH utility toward B |
| Utility INVESTIGATE | `familiarity` | Higher familiarity lowers novelty and investigation utility |
| Utility FLEE / radius / proximity | `threatMemory`, `hostility`, `trust` | Raises threat response or lets trust reduce proximity/radius pressure |
| `ThreatAssessment` | `hostility`, `directThreatMemory` | Generic Pokemon or trainer candidate can become A's direct threat |
| Trainer-wariness branch | `familiarity`, `trust`, `affinity` | Trainer-only candidate classification modifier; storage remains generic |
| `Social.shouldFollowAssociate` | `trust`, `affinity` | Gates associate following and social signal propagation |
| Social Fear input | source `trust`/`affinity` | Slightly increases weighting of a known alarm source |
| Flock search ranking | `trust`, `affinity`, `familiarity` | Ranks same-species/family search candidates using A -> candidate |
| Approach satisfaction dwell | `affinity` | Higher affinity extends post-approach dwell/reacquisition suppression |
| Voluntary join threshold | `familiarity`, `trust`, `affinity`, `threatMemory` | Threshold helper exists but is not wired into ownership flow |
| Focused debug snapshot | all report fields, plus `importance` for ordering | Read-only observability, not behavior |

`lastSeenTick` has no relationship-based behavioral consumer. `importance` is now used only to order the bounded debug snapshot. `directThreatMemory`, `hostility`, trust, affinity, familiarity, and threat memory have real consumers.

## End-to-End Evidence

### Sparse creation and direction

Twenty persistent Pokemon produce 380 possible directed Pokemon-to-Pokemon pairs. With only A->B and C->D receiving meaningful contact, actual records are 2. Empty perception over 300 ticks creates no A->B or B->A record.

A observing B creates only A->B. A later, independently observed B->A record is a different table and receives different values under asymmetric distance. Mutations are never mirrored.

### Repeated contact

Using the live producer ordering (`Social.observeNearby`, then `ENTITY_SEEN`/`ENTITY_NEAR`), same-family Pidgey A->B familiarity progressed:

```text
3.88 -> 7.75 -> 11.62 -> 15.50
```

B->A did not change while only A observed B.

Same-species same-family contact receives the existing family modifier. Different-species contact still creates and updates the same generic record shape; it simply does not receive that family modifier.

### Threat provenance

A production `Perception.observe` call with `ENTITY_ATTACKED` and severity 4 produced victim->aggressor:

```text
threatMemory = 4
directThreatMemory = 4
directThreatEvidence.reason = ENTITY_ATTACKED
```

Aggressor->victim remained absent. This proves the event semantics but not live battle/world emission, because no live emitter currently exists.

Social alarm through `Fear.update` created transient social Fear and no relationship, no `directThreatMemory`, and no direct threat ID. Persistent social learning through `applySocialFear` may update general `threatMemory`, but never direct-threat provenance.

### Persistence and identity

The existing real route lifecycle test now establishes A->B through `Perception.observe`, destroys all runtime avatars, exits the map, re-enters, and rematerializes the same persistent IDs. A->B familiarity/trust/affinity survive; a fresh nearby contact may continue increasing familiarity/affinity after re-entry.

A relationship to a route member omitted from one visible subset remains in the persistent population and is still present when that exact ID appears under a later selection seed.

`RuntimeState.reset` preserves IDs and relationship objects while clearing Fear, targets, movement requests, perception contacts, and navigation/controller state.

The production save path preserves directed familiarity, trust, affinity, threat memory, direct-threat memory, hostility, and target IDs. Serialized population members now exclude `runtimeState`, so Fear, movement, social cues, and controller state do not reload.

### Behavioral consequence

With species, positions, temperament, candidates, and all other inputs fixed:

```text
LOW chooser->B (trust=0, affinity=0)
selected C, APPROACH target score = 23

HIGH chooser->B (trust=80, affinity=60)
selected B, APPROACH target score = 103
```

The same relationship-only change also raises production APPROACH utility. The consumer reads chooser->B, not B->chooser.

### Group separation

Assigning two Pokemon the same `groupId` creates no relationship and grants no familiarity, trust, or affinity. Family/group identity and directed learned relationships remain separate systems.

### Player-generic storage

Pokemon and player targets both use `entity.relationships[targetId]` and `Relationships.getOrCreate`, with the same complete field shape. Repository search found no `trustWithPlayer`, `affinityWithPlayer`, `familiarityWithPlayer`, or equivalent player-special relationship field.

There is still player-specific orchestration: calm-proximity updates and a default trust floor are applied through `PopulationManager.updatePhase0Relationship`, and threat assessment has trainer-specific wariness semantics. Those use the generic relationship record rather than separate player fields.

## Observability

Focused TRACE relationship mutations now emit only changed fields. Example:

```text
RELATIONSHIP observer=wild:route-test:0001 subject=wild:route-test:0002 event=SOCIAL_NEARBY tick=10 familiarity=0->1.875 affinity=0->1.875 lastSeenTick=0->10 importance=0.1->0.2
```

The line requires TRACE, the relationships log category, and a matching focused observer. NORMAL receives no mutation-diff records. Events with no changed tracked fields emit nothing.

`WildEcology.getFocusedRelationshipSnapshot(limit)` returns:

- total `relationshipCount`;
- a bounded list sorted by importance, recency, and target ID;
- `targetId`, familiarity, trust, affinity, threat memory, direct-threat memory, hostility, last-seen tick, and importance.

This is read-only query support. No relationship mutation controls were added to the debug UI.

## Known Gaps

- `hostility` has no organic producer; only debug overrides/tests can currently set it.
- `trust` has no direct calm inter-Pokemon producer. It can change indirectly through social fear/reassurance toward a third-party target.
- `ENTITY_ATTACKED` and `ENTITY_FLED` have relationship semantics but no live overworld emitter.
- `lastSeenTick` has no behavioral consumer.
- `importance` has no ecology consumer; it only orders debug output.
- Voluntary join reads relationship values but is not wired into the real ownership pipeline.
- Flock search intentionally restricts candidates to same species/family before relationship ranking; generic APPROACH/INVESTIGATE/threat consumers are not restricted this way.
- The live loop calls `ENTITY_NEAR` every tick at distance <=2, so familiarity can rise quickly. This audit records current behavior and does not retune it.

## Validation

- 48 of 48 Lua specs pass when run in fresh Lua 5.5 processes.
- Focused NORMAL/TRACE volume coverage passes: relationship mutation diffs are TRACE-only.
- Scoped `git diff --check` passes, with repository line-ending warnings only.
- A LuaJIT executable is not installed in this environment, so a true LuaJIT execution smoke test could not be run. Changed production syntax remains Lua 5.1-compatible.
